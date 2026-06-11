module Pdf
  # Renders a SessionNote as a Cerca-branded PDF. SessionNote has the
  # three-section narrative structure (Review / Addressed & plan /
  # Clinician impression) used by Cerca therapists.
  class SessionNoteRenderer < CercaDocument
    def render_body(pdf)
      render_meta(pdf)
      render_narratives(pdf)
      render_signature(pdf)
    end

    private

    def render_meta(pdf)
      section(pdf, "Session details") do
        field(pdf, "Session number", record.session_number)
        field(pdf, "Session date", record.session_date)
        field(pdf, "Start time", record.session_start_time&.strftime("%H:%M"))
        field(pdf, "Authored by",
          record.author&.full_name || "Unknown therapist")
        if record.appointment
          field(pdf, "Appointment ID", record.appointment.id)
        end
      end
    end

    def render_narratives(pdf)
      section(pdf, "Review") do
        narrative(pdf, "What was discussed", record.review)
      end

      section(pdf, "What was addressed & plan going forward") do
        narrative(pdf, "Addressed and plan", record.addressed_and_plan)
      end

      section(pdf, "Clinician impression") do
        narrative(pdf, "Clinician impression", record.clinician_impression)
      end
    end

    def render_signature(pdf)
      section(pdf, "Signature") do
        if record.signed?
          field(pdf, "Signed by", record.signed_by&.full_name)
          field(pdf, "Signed at",
            record.signed_at&.strftime("%-d %b %Y at %H:%M"))
        else
          pdf.fill_color "B45309"
          pdf.text "This note is a DRAFT and has not yet been signed.",
            style: :bold
          pdf.fill_color BODY_GREY
        end
      end
    end
  end
end
