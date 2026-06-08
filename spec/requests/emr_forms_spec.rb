require "rails_helper"

RSpec.describe "EMR forms (Phase 1: models + abilities)", type: :model do
  let(:therapist_user)   { create(:user, :therapist) }
  let(:other_therapist)  { create(:user, :therapist) }
  let(:admin)            { create(:user, :admin) }
  let(:client_user)      { create(:user, :client) }
  let(:client_profile)   { client_user.client_profile }

  # Establish a real appointment between therapist + client. Uses
  # :booked status (non-cancelled). Note this only creates the
  # appointment — it does NOT set current_therapist_id. Tests that
  # need "this therapist is the client's current therapist" must also
  # call set_current_therapist.
  def establish_relationship(t, c)
    tp = t.therapist_profile
    slot = AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: 1.day.from_now,
      ends_at: 1.day.from_now + 1.hour,
      status: :approved
    )
    Appointment.new(
      client_profile: c.client_profile,
      therapist_profile: tp,
      availability_slot: slot,
      status: :booked
    ).save!(validate: false)
  end

  # Pin this therapist as the client's current treating therapist
  # (v2 model). Required for ability rules that gate on
  # current_therapist_id.
  def set_current_therapist(t, c)
    c.client_profile.update!(current_therapist: t.therapist_profile)
  end

  describe "Signable concern (shared)" do
    let!(:form) {
      IntakeForm.create!(
        client_profile: client_profile,
        author: therapist_user,
        presenting_complaint: "anxiety"
      )
    }

    it "starts unsigned" do
      expect(form.signed?).to be(false)
    end

    it "signs successfully" do
      form.sign!(therapist_user)
      expect(form.signed?).to be(true)
      expect(form.signed_by).to eq(therapist_user)
    end

    it "blocks edits after signing" do
      form.sign!(therapist_user)
      form.presenting_complaint = "edited"
      expect(form.save).to be(false)
      expect(form.errors[:base]).to include(
        a_string_matching(/signed and cannot be edited/i)
      )
    end

    it "raises if signed twice" do
      form.sign!(therapist_user)
      expect { form.sign!(therapist_user) }.to raise_error(/Already signed/)
    end
  end

  describe "IntakeForm uniqueness (v2: one per client-per-therapist)" do
    it "rejects a second intake from the SAME therapist for the same client" do
      IntakeForm.create!(client_profile: client_profile, author: therapist_user)
      dup = IntakeForm.new(client_profile: client_profile, author: therapist_user)
      expect(dup.save).to be(false)
      expect(dup.errors[:client_profile_id].join).to match(/already has an intake form/)
    end

    it "allows a different therapist to create their own intake for the same client" do
      IntakeForm.create!(client_profile: client_profile, author: therapist_user)
      # After a switch, the new therapist documents their own intake.
      second = IntakeForm.new(client_profile: client_profile, author: other_therapist)
      expect(second.save).to be(true)
    end
  end

  describe "ServicePlanNote uniqueness" do
    it "rejects a second service plan for the same client" do
      ServicePlanNote.create!(client_profile: client_profile,
                              author: therapist_user)
      dup = ServicePlanNote.new(client_profile: client_profile,
                                author: therapist_user)
      expect(dup.save).to be(false)
    end
  end

  describe "DASS-42 scoring" do
    it "computes Depression/Anxiety/Stress subscale totals correctly" do
      # Fill items so each subscale has a known sum.
      # Depression items × value 2 = 28. Anxiety items × value 1 = 14.
      # Stress items × value 3 = 42. Subscales of 14 items each.
      attrs = { client_profile: client_profile, author: therapist_user,
                assessment_date: Date.current }
      DassAssessment::DEPRESSION_ITEMS.each { |i| attrs["item_#{i}".to_sym] = 2 }
      DassAssessment::ANXIETY_ITEMS.each    { |i| attrs["item_#{i}".to_sym] = 1 }
      DassAssessment::STRESS_ITEMS.each     { |i| attrs["item_#{i}".to_sym] = 3 }

      d = DassAssessment.create!(attrs)
      expect(d.depression_score).to eq(28)
      expect(d.anxiety_score).to eq(14)
      expect(d.stress_score).to eq(42)
    end

    it "assigns severity labels against published cutoffs" do
      d = DassAssessment.new(client_profile: client_profile,
                             author: therapist_user,
                             assessment_date: Date.current)
      # Depression 28 = "extremely_severe" (>= 28)
      DassAssessment::DEPRESSION_ITEMS.each { |i| d["item_#{i}"] = 2 }
      # Anxiety 14 = "moderate" (10-14)
      DassAssessment::ANXIETY_ITEMS.each    { |i| d["item_#{i}"] = 1 }
      # Stress 14 = "normal" (0-14) — give zeros for stress items
      DassAssessment::STRESS_ITEMS.each     { |i| d["item_#{i}"] = 1 }
      d.save!
      expect(d.depression_severity).to eq("extremely_severe")
      expect(d.anxiety_severity).to eq("moderate")
      expect(d.stress_severity).to eq("normal")
    end

    it "rejects items outside 0-3" do
      d = DassAssessment.new(client_profile: client_profile,
                             author: therapist_user,
                             assessment_date: Date.current,
                             item_1: 5)
      expect(d.valid?).to be(false)
      expect(d.errors[:item_1]).to include("must be 0-3")
    end
  end

  describe "WheelOfLife scoring" do
    let(:full_scores) {
      WheelOfLifeAssessment::AREAS.transform_values { |n| Array.new(n, 5) }
    }

    it "computes per-area totals + percentages" do
      w = WheelOfLifeAssessment.create!(
        client_profile: client_profile,
        author: therapist_user,
        assessment_date: Date.current,
        scores: full_scores
      )
      expect(w.totals["career"]["total"]).to eq(25)
      expect(w.totals["career"]["max"]).to eq(50)
      expect(w.totals["career"]["percentage"]).to eq(50)
      expect(w.totals["family"]["total"]).to eq(20)
      expect(w.totals["family"]["max"]).to eq(40)
      expect(w.totals["family"]["percentage"]).to eq(50)
    end

    it "rejects an area with wrong number of items" do
      bad = full_scores.merge("career" => [5, 5, 5]) # too few
      w = WheelOfLifeAssessment.new(
        client_profile: client_profile,
        author: therapist_user,
        assessment_date: Date.current,
        scores: bad
      )
      expect(w.valid?).to be(false)
      expect(w.errors[:scores]).to include(a_string_matching(/career/))
    end

    it "rejects values outside 1-10" do
      bad = full_scores.merge("career" => [5, 5, 5, 5, 11])
      w = WheelOfLifeAssessment.new(
        client_profile: client_profile,
        author: therapist_user,
        assessment_date: Date.current,
        scores: bad
      )
      expect(w.valid?).to be(false)
    end
  end

  describe "Ability — therapist who is the CURRENT therapist" do
    before do
      establish_relationship(therapist_user, client_user)
      set_current_therapist(therapist_user, client_user)
    end

    %w[IntakeForm SessionNote ServicePlanNote].each do |klass_name|
      it "lets the current therapist read/create/update #{klass_name}" do
        ability = Ability.new(therapist_user)
        klass = klass_name.constantize
        record = klass.new(client_profile: client_profile, author: therapist_user)
        expect(ability.can?(:read,   record)).to be(true)
        expect(ability.can?(:create, record)).to be(true)
        expect(ability.can?(:update, record)).to be(true)
      end
    end

    %w[DassAssessment WheelOfLifeAssessment].each do |klass_name|
      it "lets the current therapist read but NOT write #{klass_name} (client-authored)" do
        ability = Ability.new(therapist_user)
        klass = klass_name.constantize
        record = klass.new(client_profile: client_profile)
        expect(ability.can?(:read,   record)).to be(true)
        # Therapist does not author DASS/WoL; the client does.
        expect(ability.can?(:create, record)).to be(false)
      end
    end
  end

  describe "Ability — therapist who is a FORMER therapist (client switched away)" do
    let(:past_intake) {
      IntakeForm.create!(
        client_profile: client_profile,
        author: therapist_user,
        presenting_complaint: "history"
      )
    }

    before do
      establish_relationship(therapist_user, client_user)
      # Client has since switched: another therapist is current.
      set_current_therapist(other_therapist, client_user)
      past_intake # force creation
    end

    it "lets the former therapist READ records they authored" do
      ability = Ability.new(therapist_user)
      expect(ability.can?(:read, past_intake)).to be(true)
    end

    it "denies the former therapist edit on a record they authored" do
      ability = Ability.new(therapist_user)
      expect(ability.can?(:update, past_intake)).to be(false)
    end

    it "denies the former therapist read on records they did NOT author" do
      other_intake = IntakeForm.create!(
        client_profile: client_profile,
        author: other_therapist,
        presenting_complaint: "by new therapist"
      )
      ability = Ability.new(therapist_user)
      expect(ability.can?(:read, other_intake)).to be(false)
    end

    it "denies the former therapist read on DASS/WoL (client data follows client)" do
      ability = Ability.new(therapist_user)
      dass = DassAssessment.new(client_profile: client_profile)
      wol  = WheelOfLifeAssessment.new(client_profile: client_profile)
      expect(ability.can?(:read, dass)).to be(false)
      expect(ability.can?(:read, wol)).to be(false)
    end
  end

  describe "Ability — therapist with NO relationship to client" do
    it "denies all access to other therapist's clients" do
      establish_relationship(therapist_user, client_user)
      set_current_therapist(therapist_user, client_user)
      ability = Ability.new(other_therapist) # not connected at all
      [IntakeForm, SessionNote, ServicePlanNote,
       DassAssessment, WheelOfLifeAssessment].each do |klass|
        record = klass.new(client_profile: client_profile)
        expect(ability.can?(:read,   record)).to be(false)
        expect(ability.can?(:create, record)).to be(false)
      end
    end
  end

  describe "Ability — admin" do
    it "has full manage access to all EMR forms" do
      ability = Ability.new(admin)
      [IntakeForm, SessionNote, ServicePlanNote,
       DassAssessment, WheelOfLifeAssessment].each do |klass|
        expect(ability.can?(:manage, klass)).to be(true)
      end
    end
  end

  describe "Ability — client (v2: client authors DASS/WoL)" do
    it "cannot read or write therapist-authored records" do
      ability = Ability.new(client_user)
      [IntakeForm, SessionNote, ServicePlanNote].each do |klass|
        record = klass.new(client_profile: client_profile)
        expect(ability.can?(:read,   record)).to be(false)
        expect(ability.can?(:create, record)).to be(false)
      end
    end

    it "can create and read their OWN DASS and Wheel of Life records" do
      ability = Ability.new(client_user)
      [DassAssessment, WheelOfLifeAssessment].each do |klass|
        record = klass.new(client_profile: client_profile)
        expect(ability.can?(:create, record)).to be(true)
        expect(ability.can?(:read,   record)).to be(true)
      end
    end

    it "cannot read another client's DASS/WoL records" do
      other_client = create(:user, :client)
      ability = Ability.new(client_user)
      foreign_dass = DassAssessment.new(client_profile: other_client.client_profile)
      expect(ability.can?(:read, foreign_dass)).to be(false)
    end
  end
end
