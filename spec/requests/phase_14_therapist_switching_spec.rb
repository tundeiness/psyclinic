require "rails_helper"

RSpec.describe "Phase 14: therapist switching", type: :request do
  let(:therapist_a) { create(:user, :therapist) }
  let(:tp_a) { therapist_a.therapist_profile }
  let(:therapist_b) { create(:user, :therapist) }
  let(:tp_b) { therapist_b.therapist_profile }
  let(:client_user) { create(:user, :client) }
  let(:cp) { client_user.client_profile }

  before do
    cp.update!(current_therapist: tp_a)
    sign_contract_for!(cp)
  end

  # Helper: make_paid_block from Phase 13 pattern.
  def make_paid_block(client:, therapist:, sessions_used: 0)
    block = SessionBlock.create!(
      client_profile: client,
      therapist_profile: therapist,
      purchased_at: Time.current,
      sessions_total: 6,
      sessions_used: sessions_used,
      payment_mode: :full,
      status: :active
    )
    payment = Payment.create!(
      payable: block, client_profile: client,
      amount_cents: 30_000_000, currency: "USD",
      status: :succeeded, paid_at: Time.current,
      provider_reference: SecureRandom.uuid
    )
    block.update_columns(first_payment_id: payment.id)
    block.reload
  end

  describe "SwitchTherapist service" do
    it "happy path: closes old assignment, opens new, forfeits block" do
      # Pre-existing assignment to A.
      ClientTherapistAssignment.create!(
        client_profile: cp,
        from_therapist: nil,
        to_therapist: tp_a,
        started_at: 1.month.ago
      )
      block = make_paid_block(client: cp, therapist: tp_a, sessions_used: 2)

      r = SwitchTherapist.call(
        client_profile: cp,
        new_therapist: tp_b,
        reason: "schedule conflict"
      )

      expect(r.success?).to be(true)
      expect(cp.reload.current_therapist_id).to eq(tp_b.id)
      expect(block.reload.status).to eq("forfeited")

      open_assignments = ClientTherapistAssignment.where(client_profile_id: cp.id, ended_at: nil)
      expect(open_assignments.count).to eq(1)
      expect(open_assignments.first.to_therapist_id).to eq(tp_b.id)
      expect(open_assignments.first.from_therapist_id).to eq(tp_a.id)
      expect(open_assignments.first.forfeited_block_id).to eq(block.id)
      expect(open_assignments.first.forfeited_sessions_count).to eq(4)
      expect(open_assignments.first.reason).to eq("schedule conflict")
    end

    it "refuses when new therapist == current therapist" do
      r = SwitchTherapist.call(client_profile: cp, new_therapist: tp_a)
      expect(r.success?).to be(false)
      expect(r.code).to eq(:same_therapist)
    end

    it "refuses when there are pending appointments with current therapist" do
      slot = AvailabilitySlot.create!(
        therapist_profile: tp_a,
        starts_at: 2.days.from_now,
        ends_at: 2.days.from_now + 1.hour,
        status: :approved
      )
      Appointment.create!(
        client_profile: cp,
        therapist_profile: tp_a,
        availability_slot: slot,
        status: :booked
      )

      r = SwitchTherapist.call(client_profile: cp, new_therapist: tp_b)
      expect(r.success?).to be(false)
      expect(r.code).to eq(:pending_appointments)
      expect(cp.reload.current_therapist_id).to eq(tp_a.id)  # unchanged
    end

    it "doesn't forfeit when there's no active block" do
      r = SwitchTherapist.call(client_profile: cp, new_therapist: tp_b)
      expect(r.success?).to be(true)
      expect(r.forfeited_block).to be_nil
      expect(r.assignment.forfeited_sessions_count).to eq(0)
    end

    it "ignores blocks owned by other therapists when forfeiting" do
      # An unrelated, completed historical block should not be touched.
      other_block = make_paid_block(client: cp, therapist: tp_b)
      other_block.update_columns(status: 1)  # :completed

      r = SwitchTherapist.call(client_profile: cp, new_therapist: tp_b)
      expect(r.success?).to be(true)
      expect(other_block.reload.status).to eq("completed")
    end
  end

  describe "POST /api/v1/client/therapist_switches" do
    it "switches and returns assignment payload" do
      make_paid_block(client: cp, therapist: tp_a, sessions_used: 1)

      post "/api/v1/client/therapist_switches",
        params: { to_therapist_profile_id: tp_b.id, reason: "trying someone new" },
        headers: auth_header_for(client_user)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["assignment"]["to_therapist_id"]).to eq(tp_b.id)
      expect(body["forfeited_sessions_count"]).to eq(5)
    end

    it "rejects with same_therapist code when not actually switching" do
      post "/api/v1/client/therapist_switches",
        params: { to_therapist_profile_id: tp_a.id },
        headers: auth_header_for(client_user)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["code"]).to eq("same_therapist")
    end

    it "404s on unknown therapist" do
      post "/api/v1/client/therapist_switches",
        params: { to_therapist_profile_id: 99999 },
        headers: auth_header_for(client_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/client/therapist_switches/preview" do
    it "describes what would be forfeited" do
      make_paid_block(client: cp, therapist: tp_a, sessions_used: 2)

      get "/api/v1/client/therapist_switches/preview",
        params: { to_therapist_profile_id: tp_b.id },
        headers: auth_header_for(client_user)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["forfeited_sessions_count"]).to eq(4)
      expect(body["can_switch"]).to be(true)
      expect(body["current_therapist"]["id"]).to eq(tp_a.id)
      expect(body["new_therapist"]["id"]).to eq(tp_b.id)
    end

    it "flags can_switch=false when pending appointments exist" do
      slot = AvailabilitySlot.create!(
        therapist_profile: tp_a,
        starts_at: 2.days.from_now,
        ends_at: 2.days.from_now + 1.hour,
        status: :approved
      )
      Appointment.create!(
        client_profile: cp,
        therapist_profile: tp_a,
        availability_slot: slot,
        status: :booked
      )

      get "/api/v1/client/therapist_switches/preview",
        params: { to_therapist_profile_id: tp_b.id },
        headers: auth_header_for(client_user)
      body = JSON.parse(response.body)
      expect(body["can_switch"]).to be(false)
      expect(body["pending_appointments_count"]).to eq(1)
    end
  end

  describe "EMR access boundary after switching (Phase 1 ability rules)" do
    it "prior therapist retains read on intake form they authored" do
      # tp_a writes an intake.
      intake = IntakeForm.create!(
        client_profile: cp,
        author: therapist_a,
        presenting_complaint: "anxiety"
      )

      # Switch to tp_b.
      SwitchTherapist.call(client_profile: cp, new_therapist: tp_b)

      ability_a = Ability.new(therapist_a)
      ability_b = Ability.new(therapist_b)
      expect(ability_a.can?(:read, intake)).to be(true)    # author
      expect(ability_a.can?(:update, intake)).to be(false) # no longer current
      expect(ability_b.can?(:read, intake)).to be(true)    # now current
    end

    it "prior therapist loses DASS read after switch" do
      dass = DassAssessment.create!(
        client_profile: cp,
        author: client_user,
        assessment_date: Date.current
      )

      SwitchTherapist.call(client_profile: cp, new_therapist: tp_b)

      ability_a = Ability.new(therapist_a)
      ability_b = Ability.new(therapist_b)
      expect(ability_a.can?(:read, dass)).to be(false)  # client-authored
      expect(ability_b.can?(:read, dass)).to be(true)
    end
  end
end
