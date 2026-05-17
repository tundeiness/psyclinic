require "rails_helper"

# These specs verify the booking/pairing DOMAIN LOGIC and AUTHORIZATION
# rules directly (service objects, models, CanCanCan abilities) rather
# than through the HTTP layer. The real HTTP auth path is already covered
# by auth_spec.rb (signup + login hit the actual endpoints). Testing the
# domain directly is deterministic and isolates business correctness from
# test-harness session/token concerns.
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

  describe "PairClientWithTherapist" do
    it "pairs a client with an active therapist" do
      result = PairClientWithTherapist.call(client_profile: cp, therapist_profile: tp)
      expect(result.success?).to be(true)
      expect(cp.reload.therapist_profile_id).to eq(tp.id)
    end

    it "refuses to pair with an inactive therapist" do
      tp.update!(active: false)
      result = PairClientWithTherapist.call(client_profile: cp, therapist_profile: tp)
      expect(result.success?).to be(false)
      expect(cp.reload.therapist_profile_id).to be_nil
    end
  end

  describe "BookAppointment" do
    before { cp.update!(therapist_profile: tp) }

    it "books an approved, free slot" do
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

  describe "Ability (authorization rules)" do
    it "lets an admin manage clients and approve slots" do
      admin = create(:user, :admin)
      ability = Ability.new(admin)
      expect(ability.can?(:read, ClientProfile)).to be(true)
      expect(ability.can?(:approve, AvailabilitySlot.new)).to be(true)
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
