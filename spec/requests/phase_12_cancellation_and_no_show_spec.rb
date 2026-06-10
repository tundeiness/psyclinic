require "rails_helper"

RSpec.describe "Phase 12: 24-hour reschedule rule + no-show tracking", type: :request do
  let(:therapist) { create(:user, :therapist) }
  let(:tp) { therapist.therapist_profile }
  let(:client_user) { create(:user, :client) }
  let(:cp) { client_user.client_profile }

  before { cp.update!(current_therapist: tp) }

  # Builds a booked appointment directly (skipping the slot-availability
  # / payment flow). For tests of cancellation rules and no-show sweeps,
  # we just need a persisted booked appointment with a given slot start.
  #
  # The AvailabilitySlot model forbids past starts_at on save, so for
  # backdating we create with future times and then update_columns to
  # set the real (possibly past) times — bypassing validations.
  def make_booked(starts_at:)
    slot = AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: 1.year.from_now,
      ends_at: 1.year.from_now + 1.hour,
      status: :approved
    )
    slot.update_columns(starts_at: starts_at, ends_at: starts_at + 1.hour)
    appt = Appointment.new(
      client_profile: cp,
      therapist_profile: tp,
      availability_slot: slot,
      status: :booked
    )
    appt.save!(validate: false)
    appt
  end

  describe "DELETE /api/v1/client/appointments/:id (24-hour rule)" do
    it "rejects cancellation within 24 hours" do
      appt = make_booked(starts_at: 12.hours.from_now)

      delete "/api/v1/client/appointments/#{appt.id}",
        headers: auth_header_for(client_user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["code"]).to eq("cancellation_too_late")
      expect(appt.reload.status).to eq("booked")
    end

    it "allows cancellation more than 24 hours out" do
      appt = make_booked(starts_at: 2.days.from_now)

      delete "/api/v1/client/appointments/#{appt.id}",
        headers: auth_header_for(client_user)

      expect(response).to have_http_status(:ok)
      expect(appt.reload.status).to eq("cancelled")
    end

    it "records the cancellation reason when provided" do
      appt = make_booked(starts_at: 2.days.from_now)

      delete "/api/v1/client/appointments/#{appt.id}",
        params: { cancellation_reason: "feeling unwell" },
        headers: auth_header_for(client_user)

      expect(response).to have_http_status(:ok)
      expect(appt.reload.cancellation_reason).to eq("feeling unwell")
    end

    it "lets a pending_payment appointment cancel inside the 24h window" do
      # The 24h gate is for committed booked sessions only; pending
      # payments aren't truly holding anything.
      appt = make_booked(starts_at: 6.hours.from_now)
      appt.update_columns(status: 3)  # :pending_payment

      delete "/api/v1/client/appointments/#{appt.id}",
        headers: auth_header_for(client_user)

      expect(response).to have_http_status(:ok)
      expect(appt.reload.status).to eq("cancelled")
    end
  end

  describe "SweepNoShows" do
    it "flips a booked appointment whose slot ended >1 hour ago" do
      appt = make_booked(starts_at: 2.hours.ago)  # ended ~1 hour ago
      # Force ends_at to be definitely past the grace period.
      appt.availability_slot.update_columns(ends_at: 2.hours.ago)

      result = SweepNoShows.call
      expect(result.marked_count).to eq(1)
      appt.reload
      expect(appt.status).to eq("no_show")
      expect(appt.no_show_marked_at).to be_present
    end

    it "leaves alone an appointment within the grace period" do
      appt = make_booked(starts_at: 30.minutes.ago)
      # ended ~30 min ago — inside the 1h grace.
      result = SweepNoShows.call
      expect(result.marked_count).to eq(0)
      expect(appt.reload.status).to eq("booked")
    end

    it "does not touch already-completed appointments" do
      appt = make_booked(starts_at: 3.hours.ago)
      appt.availability_slot.update_columns(ends_at: 2.hours.ago)
      appt.update!(status: :completed)

      result = SweepNoShows.call
      expect(result.marked_count).to eq(0)
      expect(appt.reload.status).to eq("completed")
    end

    it "is idempotent" do
      appt = make_booked(starts_at: 3.hours.ago)
      appt.availability_slot.update_columns(ends_at: 2.hours.ago)

      SweepNoShows.call
      result2 = SweepNoShows.call
      expect(result2.marked_count).to eq(0)
      expect(appt.reload.status).to eq("no_show")
    end

    it "scopes by therapist when provided" do
      other_tp = create(:user, :therapist).therapist_profile
      mine = make_booked(starts_at: 3.hours.ago)
      mine.availability_slot.update_columns(ends_at: 2.hours.ago)

      other_slot = AvailabilitySlot.create!(
        therapist_profile: other_tp,
        starts_at: 1.year.from_now,
        ends_at: 1.year.from_now + 1.hour,
        status: :approved
      )
      other_slot.update_columns(starts_at: 3.hours.ago, ends_at: 2.hours.ago)
      other_client = create(:user, :client).client_profile
      other_appt = Appointment.new(
        client_profile: other_client,
        therapist_profile: other_tp,
        availability_slot: other_slot,
        status: :booked
      )
      other_appt.save!(validate: false)

      SweepNoShows.call(therapist_profile: tp)
      expect(mine.reload.status).to eq("no_show")
      expect(other_appt.reload.status).to eq("booked")  # left alone
    end
  end

  describe "ClientProfile#consecutive_no_shows" do
    def make_past(status:, days_ago:)
      starts_at = days_ago.days.ago
      slot = AvailabilitySlot.create!(
        therapist_profile: tp,
        starts_at: 1.year.from_now,
        ends_at: 1.year.from_now + 1.hour,
        status: :approved
      )
      slot.update_columns(starts_at: starts_at, ends_at: starts_at + 1.hour)
      appt = Appointment.new(
        client_profile: cp,
        therapist_profile: tp,
        availability_slot: slot,
        status: status
      )
      appt.save!(validate: false)
      appt
    end

    it "returns 0 when no missed sessions" do
      make_past(status: :completed, days_ago: 7)
      expect(cp.consecutive_no_shows).to eq(0)
    end

    it "counts consecutive no_shows ending at the most recent" do
      make_past(status: :no_show, days_ago: 1)
      make_past(status: :no_show, days_ago: 8)
      make_past(status: :no_show, days_ago: 15)
      make_past(status: :completed, days_ago: 22)
      expect(cp.consecutive_no_shows).to eq(3)
    end

    it "resets the streak at the most recent :completed" do
      make_past(status: :no_show, days_ago: 1)
      make_past(status: :completed, days_ago: 8)
      make_past(status: :no_show, days_ago: 15)
      expect(cp.consecutive_no_shows).to eq(1)
    end

    it "treats :cancelled as neither resetting nor counting" do
      make_past(status: :no_show, days_ago: 1)
      make_past(status: :cancelled, days_ago: 8)
      make_past(status: :no_show, days_ago: 15)
      expect(cp.consecutive_no_shows).to eq(2)
    end

    it "treatment_review_recommended? at 3 no-shows" do
      3.times.with_index do |_, i|
        make_past(status: :no_show, days_ago: (i + 1) * 7)
      end
      expect(cp.treatment_review_recommended?).to be(true)
    end

    it "treatment_review_recommended? false at 2 no-shows" do
      make_past(status: :no_show, days_ago: 7)
      make_past(status: :no_show, days_ago: 14)
      expect(cp.treatment_review_recommended?).to be(false)
    end
  end
end
