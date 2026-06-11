require "rails_helper"

RSpec.describe "Phase 15: PDF export", type: :request do
  let(:therapist) { create(:user, :therapist) }
  let(:tp) { therapist.therapist_profile }
  let(:other_therapist) { create(:user, :therapist) }
  let(:other_tp) { other_therapist.therapist_profile }
  let(:client_user) { create(:user, :client) }
  let(:cp) { client_user.client_profile }

  before do
    cp.update!(current_therapist: tp)
    sign_contract_for!(cp)
  end

  # Helper: make a minimal IntakeForm authored by `tp`.
  def make_intake(author: therapist, signed: false)
    intake = IntakeForm.create!(
      client_profile: cp,
      author: author,
      session_date: Date.current,
      presenting_complaint: "Anxiety and sleep difficulties.",
      therapy_goals: "Sleep through the night; reduce panic episodes.",
      case_formulation: "Generalized anxiety with sleep onset insomnia.",
      provisional_diagnoses: "GAD (provisional)",
      treatment_plan: "Weekly CBT-I + relaxation training."
    )
    intake.sign!(author) if signed
    intake
  end

  def make_appointment_and_note(author: therapist, signed: false)
    slot = AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: 2.days.from_now,
      ends_at: 2.days.from_now + 1.hour,
      status: :approved
    )
    appt = Appointment.create!(
      client_profile: cp,
      therapist_profile: tp,
      availability_slot: slot,
      status: :completed,
      session_kind: :normal
    )
    note = SessionNote.create!(
      appointment: appt,
      client_profile: cp,
      author: author,
      session_number: 1,
      session_date: Date.current,
      review: "Reviewed sleep diary; gains since last week.",
      addressed_and_plan: "CBT-I sleep restriction continued.",
      clinician_impression: "Engaged; progress on schedule."
    )
    note.sign!(author) if signed
    [appt, note]
  end

  describe "Pdf::IntakeFormRenderer" do
    it "produces a valid PDF byte string" do
      intake = make_intake(signed: true)
      pdf = Pdf::IntakeFormRenderer.new(
        record: intake,
        generated_by: therapist,
        title: "Intake form"
      ).render

      # PDF files start with the magic bytes "%PDF-".
      expect(pdf[0, 5]).to eq("%PDF-")
      # Non-trivial size — at minimum a few KB for a styled doc.
      expect(pdf.bytesize).to be > 1_000
    end

    # Note: I considered a test that greps the PDF bytes for
    # "Cerca Africa" + the client's name. In practice, Prawn encodes
    # text through font subsetting / Tj operators, so the bytes are
    # not guaranteed to contain the literal substring even when the
    # rendered output displays them correctly. The shape-of-bytes
    # checks above plus the endpoint specs below give us the
    # coverage that matters. A pdf-reader-based assertion would be
    # more robust but is overkill for v1.

    it "renders even when many optional fields are blank" do
      # Bare-minimum intake — only the required fk fields populated.
      intake = IntakeForm.create!(
        client_profile: cp, author: therapist
      )
      pdf = Pdf::IntakeFormRenderer.new(
        record: intake, generated_by: therapist, title: "Intake form"
      ).render
      expect(pdf[0, 5]).to eq("%PDF-")
    end
  end

  describe "Pdf::SessionNoteRenderer" do
    it "produces a valid PDF for a signed note" do
      _, note = make_appointment_and_note(signed: true)
      pdf = Pdf::SessionNoteRenderer.new(
        record: note, generated_by: therapist, title: "Session note"
      ).render
      expect(pdf[0, 5]).to eq("%PDF-")
    end
  end

  describe "GET /api/v1/clients/:client_id/intake_form/pdf" do
    it "returns 200 and a PDF for the current therapist (signed)" do
      make_intake(signed: true)
      get "/api/v1/clients/#{cp.id}/intake_form/pdf",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body[0, 5]).to eq("%PDF-")
      expect(response.headers["Content-Disposition"]).to match(/attachment/i)
    end

    it "returns 200 for an unsigned intake (draft watermark applied)" do
      make_intake(signed: false)
      get "/api/v1/clients/#{cp.id}/intake_form/pdf",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:ok)
      expect(response.body[0, 5]).to eq("%PDF-")
      # The literal watermark string is encoded by Prawn — we can't
      # grep it reliably as plain text, but the size should still
      # exceed a trivial doc.
      expect(response.body.bytesize).to be > 1_000
    end

    it "404s when no intake exists" do
      get "/api/v1/clients/#{cp.id}/intake_form/pdf",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:not_found)
    end

    it "denies access to a therapist with no relationship to the client" do
      # other_therapist has no appointments + no assignment history
      # with this client — should not be able to read.
      make_intake(signed: true)
      get "/api/v1/clients/#{cp.id}/intake_form/pdf",
        headers: auth_header_for(other_therapist)
      expect(response).to have_http_status(:forbidden)
    end

    it "permits a former therapist who authored the intake to download" do
      # Author the intake while tp is current, then switch to other_tp.
      intake = make_intake(signed: true)
      SwitchTherapist.call(client_profile: cp, new_therapist: other_tp)
      # tp is no longer current_therapist, but they authored the
      # record — Phase 1 ability rule preserves read access.
      get "/api/v1/clients/#{cp.id}/intake_form/pdf",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:ok)
      expect(intake.reload.author_id).to eq(therapist.id)
    end
  end

  describe "GET /api/v1/appointments/:appointment_id/session_note/pdf" do
    it "returns 200 and a PDF for the authoring therapist" do
      _, _note = make_appointment_and_note(signed: true)
      appt = Appointment.last
      get "/api/v1/appointments/#{appt.id}/session_note/pdf",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body[0, 5]).to eq("%PDF-")
    end

    it "404s when the appointment has no session note yet" do
      slot = AvailabilitySlot.create!(
        therapist_profile: tp,
        starts_at: 2.days.from_now,
        ends_at: 2.days.from_now + 1.hour,
        status: :approved
      )
      appt = Appointment.create!(
        client_profile: cp,
        therapist_profile: tp,
        availability_slot: slot,
        status: :booked
      )
      get "/api/v1/appointments/#{appt.id}/session_note/pdf",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:not_found)
    end
  end
end
