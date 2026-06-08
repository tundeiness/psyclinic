require "rails_helper"

RSpec.describe "Increment 5a: welcome, dashboard, reminders" do
  include ActiveJob::TestHelper

  let(:json) { JSON.parse(response.body) }

  # ---- Public welcome page (unauthenticated) ----
  describe "GET /api/v1/public/therapists", type: :request do
    it "lists approved, active therapists without authentication" do
      approved = create(:user, :therapist) # factory default = approved
      approved.therapist_profile.update!(headline: "Anxiety specialist",
                                         hourly_rate_cents: 9000, active: true)

      pending = create(:user, :therapist, :pending)
      pending.therapist_profile.update!(active: true)

      get "/api/v1/public/therapists"
      expect(response).to have_http_status(:ok)

      ids = json["therapists"].map { |t| t["id"] }
      expect(ids).to include(approved.therapist_profile.id)
      expect(ids).not_to include(pending.therapist_profile.id)
      expect(json["therapists"].first).to include("headline", "bio", "hourly_rate_cents")
    end

    it "excludes inactive therapist profiles" do
      t = create(:user, :therapist)
      t.therapist_profile.update!(active: false)
      get "/api/v1/public/therapists"
      expect(json["therapists"].map { |x| x["id"] }).not_to include(t.therapist_profile.id)
    end
  end

  # ---- Admin dashboard ----
  describe "GET /api/v1/admin/dashboard", type: :request do
    it "requires authentication" do
      get "/api/v1/admin/dashboard"
      expect(response).to have_http_status(:unauthorized)
    end

    it "forbids a non-admin" do
      client = create(:user, :client)
      get "/api/v1/admin/dashboard", headers: auth_header_for(client)
      expect(response).to have_http_status(:forbidden)
    end

    it "returns counts, pending applications and payment inflows for an admin" do
      admin = create(:user, :admin)
      create(:user, :client, :pending)
      create(:user, :therapist)

      tp = create(:user, :therapist).therapist_profile
      tp.update!(hourly_rate_cents: 5000)
      AppSetting.current.update!(
        flat_rate_cents: 5000,
        assessment_session_price_cents: 5000
      )
      cp = create(:user, :client).client_profile

      # Burn the client's free first session so the next booking is paid
      # under the first-free-then-flat-rate rule. Insert directly to
      # bypass slot/booking validations.
      prior_slot = AvailabilitySlot.create!(therapist_profile: tp,
        starts_at: 4.days.from_now, ends_at: 4.days.from_now + 1.hour,
        status: :approved)
      Appointment.new(client_profile: cp, therapist_profile_id: tp.id,
        availability_slot: prior_slot, status: :booked).save!(validate: false)

      slot = AvailabilitySlot.create!(therapist_profile: tp,
        starts_at: 2.days.from_now, ends_at: 2.days.from_now + 1.hour,
        status: :approved)
      booking = BookAppointment.call(client_profile: cp, availability_slot_id: slot.id, session_kind: :assessment)
      ConfirmPayment.call(payment: booking.payment)

      get "/api/v1/admin/dashboard", headers: auth_header_for(admin)
      expect(response).to have_http_status(:ok)
      expect(json["counts"]).to include("clients", "therapists",
        "pending_applications", "blog_posts", "blog_posts_published")
      expect(json["pending_applications"]).to be_an(Array)
      expect(json.dig("payment_inflows", "total_cents")).to eq(5000)
      expect(json.dig("payment_inflows", "count")).to eq(1)
      expect(json["calendar"]).to include("availability", "appointments")
      # New widgets — shape only here; deeper assertions live in
      # dashboard_widgets_spec.rb.
      expect(json["bookings_by_day"]).to be_an(Array)
      expect(json["status_breakdown"]).to be_a(Hash)
      expect(json["top_therapists"]).to be_an(Array)
    end
  end

  # ---- Reminder logic (no scheduler needed) ----
  describe "SendAppointmentReminders" do
    def booked_appointment(starts_in:)
      tp = create(:user, :therapist).therapist_profile
      cp = create(:user, :client).client_profile
      tp.update!(hourly_rate_cents: 4000)
      slot = AvailabilitySlot.create!(therapist_profile: tp,
        starts_at: starts_in.from_now, ends_at: starts_in.from_now + 1.hour,
        status: :approved)
      b = BookAppointment.call(client_profile: cp, availability_slot_id: slot.id, session_kind: :assessment)
      ConfirmPayment.call(payment: b.payment)
      b.appointment.reload
    end

    before { ActionMailer::Base.deliveries.clear }

    it "reminds therapists for sessions within the 2-day window" do
      appt = booked_appointment(starts_in: 1.day)
      result = nil
      perform_enqueued_jobs { result = SendAppointmentReminders.call }

      expect(result.reminded_count).to eq(1)
      expect(appt.reload.reminder_sent_at).to be_present
      expect(appt.therapist_profile.user.notifications
                 .where(kind: "appointment_reminder")).to be_exist
      expect(ActionMailer::Base.deliveries.map(&:subject))
        .to include(a_string_matching(/reminder/i))
    end

    it "does NOT remind for sessions outside the window" do
      booked_appointment(starts_in: 10.days)
      result = SendAppointmentReminders.call
      expect(result.reminded_count).to eq(0)
    end

    it "is idempotent — does not double-remind" do
      booked_appointment(starts_in: 1.day)
      first = SendAppointmentReminders.call
      second = SendAppointmentReminders.call
      expect(first.reminded_count).to eq(1)
      expect(second.reminded_count).to eq(0)
    end

    it "skips appointments still pending payment" do
      tp = create(:user, :therapist).therapist_profile
      cp = create(:user, :client).client_profile
      tp.update!(hourly_rate_cents: 4000)
      slot = AvailabilitySlot.create!(therapist_profile: tp,
        starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour,
        status: :approved)
      BookAppointment.call(client_profile: cp, availability_slot_id: slot.id, session_kind: :assessment)
      # not confirmed -> still pending_payment

      result = SendAppointmentReminders.call
      expect(result.reminded_count).to eq(0)
    end
  end
end
