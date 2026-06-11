require "rails_helper"

RSpec.describe ProcessStripeEvent do
  let(:tp_user) { create(:user, :therapist) }
  let(:tp) { tp_user.therapist_profile }
  let(:cp_user) { create(:user, :client) }
  let(:cp) { cp_user.client_profile }

  before do
    AppSetting.current.update!(assessment_session_price_cents: 5_000_000)
    ActionMailer::Base.deliveries.clear
  end

  # Set up an assessment booking that's pending — i.e. exactly what
  # the webhook is about to confirm.
  def pending_assessment_booking
    slot = AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: 2.days.from_now,
      ends_at: 2.days.from_now + 1.hour,
      status: :approved
    )
    BookAppointment.call(
      client_profile: cp,
      availability_slot_id: slot.id,
      session_kind: :assessment
    )
  end

  def success_event(payment_intent_id, event_id: "evt_test_#{SecureRandom.hex(6)}")
    {
      "id" => event_id,
      "type" => "payment_intent.succeeded",
      "data" => { "object" => {
        "id" => payment_intent_id,
        "status" => "succeeded"
      } }
    }
  end

  def failure_event(payment_intent_id, event_id: "evt_test_#{SecureRandom.hex(6)}")
    {
      "id" => event_id,
      "type" => "payment_intent.payment_failed",
      "data" => { "object" => {
        "id" => payment_intent_id,
        "status" => "requires_payment_method",
        "last_payment_error" => {
          "code" => "card_declined",
          "message" => "Your card was declined."
        }
      } }
    }
  end

  describe "successful payment_intent.succeeded event" do
    it "marks payment succeeded, books appointment, and binds client to therapist" do
      booking = pending_assessment_booking
      result = ProcessStripeEvent.call(
        success_event(booking.payment.provider_reference)
      )

      expect(result.success?).to be(true)
      expect(result.payment.reload.status).to eq("succeeded")
      expect(result.appointment.reload.status).to eq("booked")
      expect(cp.reload.current_therapist_id).to eq(tp.id)
    end

    it "is idempotent: re-processing the same event id is a no-op" do
      booking = pending_assessment_booking
      ev = success_event(booking.payment.provider_reference, event_id: "evt_dup_1")

      ProcessStripeEvent.call(ev)
      # Reset the mail queue so we can prove the second call doesn't
      # notify the therapist again.
      ActionMailer::Base.deliveries.clear
      result2 = ProcessStripeEvent.call(ev)

      expect(result2.success?).to be(true)
      expect(result2.ignored).to be(true)
      expect(ActionMailer::Base.deliveries.size).to eq(0)
    end

    it "refuses to book an assessment with a non-current therapist (Phase 14)" do
      # Phase 14 hardening: previously, a client with a current
      # therapist could book an assessment with someone else; the
      # webhook would deliver the payment but NOT auto-switch the
      # binding, leaving them paid up but still bound to their
      # original therapist (a quiet trap). The fix refuses the
      # booking upstream so the client is pushed to the explicit
      # SwitchTherapist flow that explains the forfeit and consents.
      other_tp = create(:user, :therapist).therapist_profile
      cp.update!(current_therapist_id: other_tp.id)

      # The slot belongs to `tp` (not `other_tp`), so it's a different
      # therapist than the client's current one.
      slot = AvailabilitySlot.create!(
        therapist_profile: tp,
        starts_at: 2.days.from_now,
        ends_at: 2.days.from_now + 1.hour,
        status: :approved
      )

      result = BookAppointment.call(
        client_profile: cp,
        availability_slot_id: slot.id,
        session_kind: :assessment
      )

      expect(result.success?).to be(false)
      expect(result.error).to match(/current therapist.*switch/i)

      # Binding remains untouched.
      expect(cp.reload.current_therapist_id).to eq(other_tp.id)
    end
  end

  describe "failed payment_intent.payment_failed event" do
    it "marks payment failed and flips appointment to payment_failed" do
      booking = pending_assessment_booking
      result = ProcessStripeEvent.call(
        failure_event(booking.payment.provider_reference)
      )

      expect(result.success?).to be(false)
      expect(result.payment.reload.status).to eq("failed")
      expect(result.appointment.reload.status).to eq("payment_failed")
    end
  end

  describe "ignored events" do
    it "ack-ignores event types we don't handle" do
      result = ProcessStripeEvent.call({
        "id" => "evt_test_x", "type" => "customer.created",
        "data" => { "object" => {} }
      })
      expect(result.success?).to be(true)
      expect(result.ignored).to be(true)
    end

    it "ack-ignores events for unknown payment intents" do
      result = ProcessStripeEvent.call(success_event("pi_test_unknown"))
      expect(result.success?).to be(true)
      expect(result.ignored).to be(true)
    end
  end

  describe "malformed events" do
    it "returns an error result for events missing an id" do
      result = ProcessStripeEvent.call({
        "type" => "payment_intent.succeeded",
        "data" => { "object" => { "id" => "pi_test_x" } }
      })
      expect(result.success?).to be(false)
      expect(result.error).to match(/missing id/i)
    end

    it "returns an error result for events missing an intent id" do
      result = ProcessStripeEvent.call({
        "id" => "evt_test_x",
        "type" => "payment_intent.succeeded",
        "data" => { "object" => {} }
      })
      expect(result.success?).to be(false)
      expect(result.error).to match(/missing payment intent id/i)
    end
  end
end
