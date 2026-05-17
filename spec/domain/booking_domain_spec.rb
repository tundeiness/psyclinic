require "rails_helper"

# Verifies booking DOMAIN LOGIC and AUTHORIZATION rules directly (service
# objects, models, CanCanCan abilities). Pairing has been removed: a
# client may book any approved, free slot from any therapist.
RSpec.describe "Booking domain" do
  let(:therapist_user) { create(:user, :therapist) }
  let(:client_user)    { create(:user, :client) }
  let(:tp)             { therapist_user.therapist_profile }
  let(:cp)             { client_user.client_profile }

  def make_slot(status: :approved, starts_in: 2.days)
    AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: starts_in.from_now,
      ends_at: starts_in.from_now + 1.hour,
      status: status
    )
  end

  describe "BookAppointment" do
    it "books an approved, free slot (no pairing required)" do
      s = make_slot(status: :approved)
      result = BookAppointment.call(client_profile: cp, availability_slot_id: s.id, reason: "First")
      expect(result.success?).to be(true)
      expect(result.appointment).to be_persisted
      expect(s.reload.booked?).to be(true)
    end

    it "rejects booking an unapproved (proposed) slot" do
      s = make_slot(status: :proposed)
      result = BookAppointment.call(client_profile: cp, availability_slot_id: s.id)
      expect(result.success?).to be(false)
      expect(result.error).to match(/not available/i)
    end

    it "rejects booking a missing slot" do
      result = BookAppointment.call(client_profile: cp, availability_slot_id: -1)
      expect(result.success?).to be(false)
      expect(result.error).to match(/not found/i)
    end

    it "prevents double-booking the same slot" do
      s = make_slot(status: :approved)
      first = BookAppointment.call(client_profile: cp, availability_slot_id: s.id)
      expect(first.success?).to be(true)

      second = BookAppointment.call(client_profile: cp, availability_slot_id: s.id)
      expect(second.success?).to be(false)
      expect(second.error).to match(/already booked/i)
    end
  end

  describe "TherapistProfile#clients_with_appointments" do
    it "returns clients who have a non-cancelled appointment" do
      s = make_slot(status: :approved)
      BookAppointment.call(client_profile: cp, availability_slot_id: s.id)
      expect(tp.clients_with_appointments).to include(cp)
    end

    it "excludes clients with no appointments" do
      expect(tp.clients_with_appointments).not_to include(cp)
    end
  end

  describe "Ability (authorization rules)" do
    it "lets an admin manage clients and approve slots" do
      admin = create(:user, :admin)
      ability = Ability.new(admin)
      expect(ability.can?(:read, ClientProfile)).to be(true)
      expect(ability.can?(:approve, AvailabilitySlot.new)).to be(true)
    end

    it "lets an admin manage users (approve/reject applications)" do
      admin = create(:user, :admin)
      expect(Ability.new(admin).can?(:manage, User)).to be(true)
    end

    it "lets a therapist create their own availability slots" do
      ability = Ability.new(therapist_user)
      own_slot = AvailabilitySlot.new(therapist_profile_id: tp.id)
      expect(ability.can?(:create, own_slot)).to be(true)
    end

    it "does NOT let a therapist author another therapist's slots" do
      other = create(:user, :therapist).therapist_profile
      ability = Ability.new(therapist_user)
      foreign_slot = AvailabilitySlot.new(therapist_profile_id: other.id)
      expect(ability.can?(:create, foreign_slot)).to be(false)
    end

    it "lets a therapist read a client who booked them, not a stranger" do
      s = make_slot(status: :approved)
      BookAppointment.call(client_profile: cp, availability_slot_id: s.id)
      stranger = create(:user, :client).client_profile

      ability = Ability.new(therapist_user)
      expect(ability.can?(:read, cp)).to be(true)
      expect(ability.can?(:read, stranger)).to be(false)
    end

    it "does NOT let a client read the admin client list" do
      ability = Ability.new(client_user)
      expect(ability.can?(:read, ClientProfile)).to be(false)
    end

    it "lets a client read approved slots only" do
      ability = Ability.new(client_user)
      approved = AvailabilitySlot.new(therapist_profile_id: tp.id, status: :approved)
      proposed = AvailabilitySlot.new(therapist_profile_id: tp.id, status: :proposed)
      expect(ability.can?(:read, approved)).to be(true)
      expect(ability.can?(:read, proposed)).to be(false)
    end
  end
end
