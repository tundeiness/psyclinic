module Api
  module V1
    module Therapist
      # Therapist-facing DASS-42 endpoints. Read-only — the client
      # is the author. The therapist sees the full record including
      # raw numeric scores (which the client view hides per Q7).
      class DassAssessmentsController < ApplicationController
        before_action :authenticate_user!
        before_action :load_client_profile
        before_action :load_assessment, only: %i[show pdf]

        # GET /api/v1/therapist/clients/:client_id/dass_assessments
        # Timeline of the client's submitted assessments. Drafts
        # are excluded — the therapist sees finalized assessments
        # only (the client hasn't shared a half-completed one with
        # them yet).
        def index
          authorize! :read, DassAssessment.new(client_profile: @client_profile)
          records = @client_profile.dass_assessments
            .where.not(signed_at: nil)
            .order(assessment_date: :desc, created_at: :desc)
          render json: {
            dass_assessments: records.map { |r| serialize_for_therapist(r) }
          }
        end

        # GET /api/v1/therapist/clients/:client_id/dass_assessments/:id
        def show
          authorize! :read, @assessment
          render json: { dass_assessment: serialize_for_therapist(@assessment) }
        end

        # GET /api/v1/therapist/clients/:client_id/dass_assessments/:id/pdf
        def pdf
          authorize! :read, @assessment

          body = Pdf::DassRenderer.new(
            record: @assessment,
            generated_by: current_user,
            title: "DASS-42 assessment"
          ).render

          filename = "dass-#{@client_profile.full_name.parameterize}-" \
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
          @assessment = @client_profile.dass_assessments.find_by(id: params[:id])
          # Don't expose draft assessments to the therapist — the
          # client hasn't submitted them yet. Return 404 to keep
          # draft existence private.
          if @assessment.nil? || !@assessment.signed?
            return render_not_found
          end
        end

        # Therapist view includes raw numeric scores AND severity
        # bands AND all 42 item responses. Full clinical picture.
        def serialize_for_therapist(record)
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
