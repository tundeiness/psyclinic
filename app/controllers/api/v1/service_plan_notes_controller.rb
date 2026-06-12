module Api
  module V1
    class ServicePlanNotesController < ApplicationController
      before_action :authenticate_user!
      before_action :load_client_profile
      before_action :load_or_build_note, except: :create

      # GET /api/v1/clients/:client_id/service_plan_note
      def show
        authorize! :read, (@note || read_placeholder)
        return render_not_found unless @note
        render json: { service_plan_note: serialize(@note) }
      end

      # POST /api/v1/clients/:client_id/service_plan_note
      def create
        @note = ServicePlanNote.new(note_params.merge(
          client_profile: @client_profile,
          author: current_user
        ))
        authorize! :create, @note
        if @note.save
          render json: { service_plan_note: serialize(@note) }, status: :created
        else
          render_unprocessable(@note)
        end
      end

      # PATCH /api/v1/clients/:client_id/service_plan_note
      def update
        authorize! :update, (@note || write_placeholder)
        return render_not_found unless @note
        if @note.update(note_params)
          render json: { service_plan_note: serialize(@note) }
        else
          render_unprocessable(@note)
        end
      end

      # POST /api/v1/clients/:client_id/service_plan_note/sign
      def sign
        authorize! :update, (@note || write_placeholder)
        return render_not_found unless @note
        if @note.signed?
          return render json: {
            error: { code: :already_signed, message: "Already signed" }
          }, status: :unprocessable_entity
        end
        @note.sign!(current_user)
        render json: { service_plan_note: serialize(@note) }
      end

      # GET /api/v1/clients/:client_id/service_plan_note/pdf
      # Watermarked when unsigned (Phase 15 base class behavior).
      def pdf
        authorize! :read, (@note || read_placeholder)
        return render_not_found unless @note

        body = Pdf::ServicePlanNoteRenderer.new(
          record: @note,
          generated_by: current_user,
          title: "Service plan note"
        ).render

        filename = "service-plan-#{@client_profile.full_name.parameterize}-" \
                   "#{Date.current.iso8601}.pdf"
        send_data body,
          type: "application/pdf",
          disposition: "attachment",
          filename: filename
      end

      private

      def read_placeholder
        # Author is nil so the author-match read rule cannot
        # accidentally pass for whoever is asking.
        ServicePlanNote.new(client_profile: @client_profile, author: nil)
      end

      def write_placeholder
        ServicePlanNote.new(client_profile: @client_profile, author: current_user)
      end

      def load_client_profile
        @client_profile = ClientProfile.find_by(id: params[:client_id])
        render_not_found unless @client_profile
      end

      def load_or_build_note
        # Service plan note is one-per-client globally (unlike intake
        # which is one-per-therapist-per-client). Therapists see the
        # plan if they're current; former therapists who AUTHORED the
        # plan retain read access (Phase 1 ability rule).
        @note = @client_profile.service_plan_note
      end

      def note_params
        params.require(:service_plan_note).permit(
          :assessment_summary,
          :presenting_problems,
          :treatment_goals,
          :interventions_planned,
          :session_frequency,
          :estimated_duration,
          :risk_considerations,
          :discharge_criteria,
          :prepared_on
        )
      end

      def serialize(note)
        note.as_json.merge(
          signed: note.signed?,
          signed_at: note.signed_at,
          signed_by_name: note.signed_by&.then { |u| "#{u.first_name} #{u.last_name}" },
          author_name: note.author&.then { |u| "#{u.first_name} #{u.last_name}" }
        )
      end

      def render_not_found
        render json: { error: { code: :not_found, message: "Service plan note not found" } },
          status: :not_found
      end

      def render_unprocessable(record)
        render json: {
          error: {
            code: :validation_failed,
            message: "Could not save the service plan note",
            details: record.errors.full_messages
          }
        }, status: :unprocessable_entity
      end
    end
  end
end
