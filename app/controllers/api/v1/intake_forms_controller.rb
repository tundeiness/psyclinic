module Api
  module V1
    class IntakeFormsController < ApplicationController
      before_action :authenticate_user!
      before_action :load_client_profile
      before_action :load_or_build_intake, except: :create

      # GET /api/v1/clients/:client_id/intake_form
      def show
        # Authorize against a placeholder with NO author so the
        # "former therapist can read records they authored" rule
        # doesn't trivially pass for whoever is asking. The real
        # record's author_id is checked only when the record exists.
        authorize! :read, (@intake || read_placeholder)
        return render_not_found unless @intake
        render json: { intake_form: serialize(@intake) }
      end

      # POST /api/v1/clients/:client_id/intake_form
      def create
        @intake = IntakeForm.new(intake_params.merge(
          client_profile: @client_profile,
          author: current_user
        ))
        authorize! :create, @intake
        if @intake.save
          render json: { intake_form: serialize(@intake) }, status: :created
        else
          render_unprocessable(@intake)
        end
      end

      # PATCH /api/v1/clients/:client_id/intake_form
      def update
        # Write placeholder carries current_user as author so the
        # current-therapist rule can evaluate. The "I authored it"
        # read shortcut doesn't apply to update — only current
        # therapist can write — so we don't have the same trap.
        authorize! :update, (@intake || write_placeholder)
        return render_not_found unless @intake
        if @intake.update(intake_params)
          render json: { intake_form: serialize(@intake) }
        else
          render_unprocessable(@intake)
        end
      end

      # POST /api/v1/clients/:client_id/intake_form/sign
      def sign
        authorize! :update, (@intake || write_placeholder)
        return render_not_found unless @intake
        if @intake.signed?
          return render json: {
            error: { code: :already_signed, message: "Already signed" }
          }, status: :unprocessable_entity
        end
        @intake.sign!(current_user)
        render json: { intake_form: serialize(@intake) }
      end

      # GET /api/v1/clients/:client_id/intake_form/pdf
      # Phase 15: PDF export. Reuses the existing read authorization
      # (which already handles the "former therapist authored this"
      # case via the ability rule). Watermarked when unsigned.
      def pdf
        authorize! :read, (@intake || read_placeholder)
        return render_not_found unless @intake

        body = Pdf::IntakeFormRenderer.new(
          record: @intake,
          generated_by: current_user,
          title: "Intake form"
        ).render

        filename = "intake-#{@client_profile.full_name.parameterize}-" \
                   "#{Date.current.iso8601}.pdf"
        send_data body,
          type: "application/pdf",
          disposition: "attachment",
          filename: filename
      end

      private

      def read_placeholder
        # Author is nil so the author-match rule cannot accidentally
        # pass for whoever is asking. Used only for authorization.
        IntakeForm.new(client_profile: @client_profile, author: nil)
      end

      def write_placeholder
        # For write checks: current_user is the real would-be author.
        IntakeForm.new(client_profile: @client_profile, author: current_user)
      end

      def load_client_profile
        @client_profile = ClientProfile.find_by(id: params[:client_id])
        render_not_found unless @client_profile
      end

      def load_or_build_intake
        # Each therapist gets their own intake form per relationship
        # with the client (post-v2 redesign). The lookup picks the
        # "most relevant" intake for the current user:
        #   - therapist: their own intake (the one they authored)
        #   - admin: the intake authored by the client's CURRENT
        #     therapist (most clinically relevant); falls back to any
        #     intake if there isn't one.
        # To view a specific intake by ID (e.g., admin looking at a
        # past therapist's intake) the record-release flow / a
        # dedicated route is the right tool (later phase).
        @intake =
          if current_user.role == "admin"
            current_id = @client_profile.current_therapist_id
            if current_id
              current_therapist_user_id =
                TherapistProfile.find(current_id).user_id
              @client_profile.intake_forms.find_by(author_id: current_therapist_user_id) ||
                @client_profile.intake_forms.order(created_at: :desc).first
            else
              @client_profile.intake_forms.order(created_at: :desc).first
            end
          else
            @client_profile.intake_form_for(current_user)
          end
      end

      # The JSONB sections need explicit array-of-hash permitting; Rails
      # would otherwise strip them silently. Each section's hash shape is
      # documented in the model.
      def intake_params
        params.require(:intake_form).permit(
          :session_date, :session_start_time, :session_end_time,
          :preferred_address, :date_of_birth, :age_at_intake, :phone_number,
          :state_of_origin, :sex, :relationship_status, :gender_identity,
          :email_address, :home_address, :profession, :work_hours,
          :religion_spirituality, :referral_source,
          :presenting_complaint, :therapy_goals,
          :self_harm_history, :self_harm_details,
          :suicidal_ideations, :suicide_plan_present, :suicide_means_available,
          :prior_therapy, :prior_therapy_details,
          :living_conditions, :other_concerns,
          :legal_proceedings, :legal_proceedings_details, :legal_proceedings_status,
          :emergency_contact_name, :emergency_contact_relationship,
          :emergency_contact_phone, :emergency_contact_address,
          :other_details,
          :case_formulation, :provisional_diagnoses, :treatment_plan,
          medications: [
            :drug, :dosage, :started, :ends, :medical_condition
          ],
          history: [
            :period, :career_academic_event, :social_details
          ],
          family_tree: [
            :relation, :relationship_progression, :current_state
          ],
          substance_use: [
            :substance, :frequency_mode, :onset_progression
          ]
        )
      end

      def serialize(intake)
        intake.as_json.merge(
          signed: intake.signed?,
          signed_at: intake.signed_at,
          signed_by_name: intake.signed_by&.then { |u| "#{u.first_name} #{u.last_name}" },
          author_name: intake.author&.then { |u| "#{u.first_name} #{u.last_name}" }
        )
      end

      def render_not_found
        render json: { error: { code: :not_found, message: "Intake form not found" } },
          status: :not_found
      end

      def render_unprocessable(record)
        render json: {
          error: {
            code: :validation_failed,
            message: "Could not save the intake form",
            details: record.errors.full_messages
          }
        }, status: :unprocessable_entity
      end
    end
  end
end
