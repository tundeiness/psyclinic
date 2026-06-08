module Api
  module V1
    class IntakeFormsController < ApplicationController
      before_action :authenticate_user!
      before_action :load_client_profile
      before_action :load_or_build_intake, except: :create

      # GET /api/v1/clients/:client_id/intake_form
      def show
        return render_not_found unless @intake
        authorize! :read, @intake
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
        return render_not_found unless @intake
        authorize! :update, @intake
        if @intake.update(intake_params)
          render json: { intake_form: serialize(@intake) }
        else
          render_unprocessable(@intake)
        end
      end

      # POST /api/v1/clients/:client_id/intake_form/sign
      def sign
        return render_not_found unless @intake
        authorize! :update, @intake
        if @intake.signed?
          return render json: {
            error: { code: :already_signed, message: "Already signed" }
          }, status: :unprocessable_entity
        end
        @intake.sign!(current_user)
        render json: { intake_form: serialize(@intake) }
      end

      private

      def load_client_profile
        @client_profile = ClientProfile.find_by(id: params[:client_id])
        render_not_found unless @client_profile
      end

      def load_or_build_intake
        @intake = @client_profile.intake_form
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
