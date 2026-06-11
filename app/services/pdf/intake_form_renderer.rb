module Pdf
  # Renders an IntakeForm as a Cerca-branded PDF.
  #
  # The intake has ~50 fields grouped into the same sections as the
  # CAMBC paper form. The layout here mirrors the FE editor at
  # /therapist/clients/[id]/intake so the printable document is
  # immediately legible to anyone who knows the on-screen form.
  class IntakeFormRenderer < CercaDocument
    def render_body(pdf)
      render_meta(pdf)
      render_personal(pdf)
      render_presenting(pdf)
      render_safety(pdf)
      render_history(pdf)
      render_psychosocial(pdf)
      render_jsonb_lists(pdf)
      render_emergency(pdf)
      render_clinical_summary(pdf)
      render_signature(pdf)
    end

    private

    def render_meta(pdf)
      section(pdf, "Session details") do
        field(pdf, "Session date", record.session_date)
        field(pdf, "Start time", record.session_start_time&.strftime("%H:%M"))
        field(pdf, "Authored by",
          record.author&.full_name || "Unknown therapist")
      end
    end

    def render_personal(pdf)
      section(pdf, "Personal information") do
        field(pdf, "Preferred name / form of address", record.preferred_address)
        field(pdf, "Date of birth", record.date_of_birth)
        field(pdf, "Age at intake", record.age_at_intake)
        field(pdf, "Sex", record.sex)
        field(pdf, "Gender identity", record.gender_identity)
        field(pdf, "Relationship status", record.relationship_status)
        field(pdf, "Phone", record.phone_number)
        field(pdf, "Email", record.email_address)
        narrative(pdf, "Home address", record.home_address)
        field(pdf, "State of origin", record.state_of_origin)
        field(pdf, "Profession", record.profession)
        narrative(pdf, "Work hours", record.work_hours)
        narrative(pdf, "Religion / spirituality", record.religion_spirituality)
        narrative(pdf, "Referral source", record.referral_source)
      end
    end

    def render_presenting(pdf)
      section(pdf, "Presenting complaint & goals") do
        narrative(pdf, "Presenting complaint", record.presenting_complaint)
        narrative(pdf, "Therapy goals", record.therapy_goals)
      end
    end

    def render_safety(pdf)
      section(pdf, "Risk & safety") do
        bool_field(pdf, "Self-harm history", record.self_harm_history)
        narrative(pdf, "Self-harm details", record.self_harm_details)
        field(pdf, "Suicidal ideations", record.suicidal_ideations)
        bool_field(pdf, "Suicide plan present", record.suicide_plan_present)
        bool_field(pdf, "Means available", record.suicide_means_available)
      end
    end

    def render_history(pdf)
      section(pdf, "Prior therapy & medical history") do
        bool_field(pdf, "Prior therapy", record.prior_therapy)
        narrative(pdf, "Prior therapy details", record.prior_therapy_details)
      end
    end

    def render_psychosocial(pdf)
      section(pdf, "Psychosocial context") do
        narrative(pdf, "Living conditions", record.living_conditions)
        narrative(pdf, "Other concerns", record.other_concerns)
        bool_field(pdf, "Legal proceedings", record.legal_proceedings)
        narrative(pdf, "Legal proceedings details",
          record.legal_proceedings_details)
        field(pdf, "Legal proceedings status",
          record.legal_proceedings_status)
      end
    end

    # Renders the four JSONB list columns (medications, history,
    # family_tree, substance_use). Each is an array of small hash
    # entries; we render as a compact list rather than a table to
    # keep layout simple and survive long free-text values that
    # would otherwise overflow narrow table columns.
    def render_jsonb_lists(pdf)
      render_list(pdf, "Medications", record.medications,
        %w[drug dosage started ends medical_condition])
      render_list(pdf, "History timeline", record.history,
        %w[period career_academic_event social_details])
      render_list(pdf, "Family tree", record.family_tree,
        %w[relation relationship_progression current_state])
      render_list(pdf, "Substance use", record.substance_use,
        %w[substance frequency_mode onset_progression])
    end

    def render_list(pdf, heading, entries, keys)
      entries = Array(entries)
      section(pdf, heading) do
        if entries.empty?
          pdf.fill_color BRAND_GREY
          pdf.font_size 9
          pdf.text "(no entries recorded)", style: :italic
          pdf.fill_color BODY_GREY
        else
          entries.each_with_index do |entry, i|
            pdf.move_down 4
            pdf.fill_color BRAND_DARK
            pdf.font_size 9
            pdf.text "Entry #{i + 1}", style: :bold
            pdf.fill_color BODY_GREY
            pdf.font_size 10
            keys.each do |k|
              v = entry.is_a?(Hash) ? (entry[k] || entry[k.to_sym]) : nil
              label = k.tr("_", " ").capitalize
              field(pdf, label, v)
            end
          end
        end
      end
    end

    def render_emergency(pdf)
      section(pdf, "Emergency contact") do
        field(pdf, "Name", record.emergency_contact_name)
        field(pdf, "Relationship", record.emergency_contact_relationship)
        field(pdf, "Phone", record.emergency_contact_phone)
        narrative(pdf, "Address", record.emergency_contact_address)
        narrative(pdf, "Other details", record.other_details)
      end
    end

    def render_clinical_summary(pdf)
      section(pdf, "Clinical summary") do
        narrative(pdf, "Case formulation", record.case_formulation)
        narrative(pdf, "Provisional diagnoses", record.provisional_diagnoses)
        narrative(pdf, "Treatment plan", record.treatment_plan)
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
          pdf.text "This record is a DRAFT and has not yet been signed.",
            style: :bold
          pdf.fill_color BODY_GREY
        end
      end
    end
  end
end
