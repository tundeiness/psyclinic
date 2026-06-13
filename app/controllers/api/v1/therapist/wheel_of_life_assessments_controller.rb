module Api
  module V1
    module Therapist
      # Phase 18.1: therapist-facing Wheel of Life read endpoints.
      # Read-only — the client is the author. Drafts are hidden until
      # the client submits (same privacy model as DASS).
      class WheelOfLifeAssessmentsController < ApplicationController
        before_action :authenticate_user!
        before_action :load_client_profile
        before_action :load_assessment, only: %i[show pdf]

        # GET /api/v1/therapist/clients/:client_id/wheel_of_life_assessments
        def index
          authorize! :read, WheelOfLifeAssessment.new(client_profile: @client_profile)
          records = @client_profile.wheel_of_life_assessments
            .where.not(signed_at: nil)
            .order(assessment_date: :desc, created_at: :desc)
          render json: {
            wheel_of_life_assessments: records.map { |r| serialize(r) }
          }
        end

        # GET /api/v1/therapist/clients/:client_id/wheel_of_life_assessments/:id
        def show
          authorize! :read, @assessment
          render json: { wheel_of_life_assessment: serialize(@assessment) }
        end

        # GET /api/v1/therapist/clients/:client_id/wheel_of_life_assessments/:id/pdf
        def pdf
          authorize! :read, @assessment

          body = Pdf::WheelOfLifeRenderer.new(
            record: @assessment,
            generated_by: current_user,
            title: "Wheel of Life assessment"
          ).render

          filename = "wheel-of-life-#{@client_profile.full_name.parameterize}-" \
                     "#{(@assessment.assessment_date || Date.current).iso8601}.pdf"
          send_data body,
            type: "application/pdf",
            disposition: "attachment",
            filename: filename
        end

        private

        def load_client_profile
          @client_profile = ClientProfile.find_by(id: params[:client_id])
          render_not_found unless @client_profile
        end

        def load_assessment
          @assessment = @client_profile.wheel_of_life_assessments.find_by(id: params[:id])
          # Drafts are private until the client submits.
          if @assessment.nil? || !@assessment.signed?
            return render_not_found
          end
        end

        def serialize(record)
          record.as_json.merge(
            signed: record.signed?,
            author_name: record.author&.then { |u| "#{u.first_name} #{u.last_name}" }
          )
        end

        def render_not_found
          render json: { error: { code: :not_found, message: "Assessment not found" } },
            status: :not_found
        end
      end
    end
  end
end
