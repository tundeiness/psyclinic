module Pdf
  # Renders a ServicePlanNote as a Cerca-branded PDF. The service
  # plan note is the structured treatment-planning record written at
  # (typically) session 2 — formalizing assessment, goals, planned
  # interventions, frequency, and discharge criteria.
  class ServicePlanNoteRenderer < CercaDocument
    def render_body(pdf)
      render_meta(pdf)
      render_assessment(pdf)
      render_plan(pdf)
      render_logistics(pdf)
      render_risk(pdf)
      render_discharge(pdf)
      render_signature(pdf)
    end

    private

    def render_meta(pdf)
      section(pdf, "Plan details") do
        field(pdf, "Prepared on", record.prepared_on)
        field(pdf, "Authored by",
          record.author&.full_name || "Unknown therapist")
      end
    end

    def render_assessment(pdf)
      section(pdf, "Assessment summary") do
        narrative(pdf, "Clinical impression",
          record.assessment_summary)
        narrative(pdf, "Presenting problems",
          record.presenting_problems)
      end
    end

    def render_plan(pdf)
      section(pdf, "Treatment plan") do
        narrative(pdf, "Treatment goals",
          record.treatment_goals)
        narrative(pdf, "Interventions planned",
          record.interventions_planned)
      end
    end

    def render_logistics(pdf)
      section(pdf, "Logistics") do
        field(pdf, "Session frequency", record.session_frequency)
        field(pdf, "Estimated duration", record.estimated_duration)
      end
    end

    def render_risk(pdf)
      section(pdf, "Risk considerations") do
        narrative(pdf, "Risk considerations",
          record.risk_considerations)
      end
    end

    def render_discharge(pdf)
      section(pdf, "Discharge criteria") do
        narrative(pdf, "Discharge criteria",
          record.discharge_criteria)
      end
    end

    def render_signature(pdf)
      section(pdf, "Signature") do
        if record.signed?
          field(pdf, "Signed by", record.signed_by&.full_name)
          field(pdf, "Signed at",
            record.signed_at&.strftime("%-d %b %Y at %H:%M"))
        else
          pdf.fill_color "B45309"  # amber-700
          pdf.text "This plan is a DRAFT and has not yet been signed.",
            style: :bold
          pdf.fill_color BODY_GREY
        end
      end
    end
  end
end
