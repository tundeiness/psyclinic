module Api
  module V1
    module Client
      # Client-facing DASS-42 endpoints. Clients author the assessment
      # themselves (DASS is a self-report instrument). Per Q7 of the
      # Phase 17 brief, clients see severity bands but NOT raw numeric
      # scores after submission — those go to the therapist only.
      class DassAssessmentsController < ApplicationController
        before_action :authenticate_user!
        before_action :ensure_client!
        before_action :load_assessment, only: %i[show update submit]
        before_action :ensure_unsigned, only: %i[update submit]

        # GET /api/v1/client/dass_assessments
        # Returns the client's own DASS history (most recent first).
        def index
          records = current_client_profile.dass_assessments
            .order(created_at: :desc)
          render json: {
            dass_assessments: records.map { |r| serialize_for_client(r) }
          }
        end

        # GET /api/v1/client/dass_assessments/:id
        def show
          authorize! :read, @assessment
          render json: { dass_assessment: serialize_for_client(@assessment) }
        end

        # POST /api/v1/client/dass_assessments
        # Starts a new draft. Returns the created record (so the FE
        # can route to its edit page). assessment_date is required
        # by the model so we set it to today.
        def create
          @assessment = DassAssessment.new(
            client_profile: current_client_profile,
            author: current_user,
            assessment_date: Date.current
          )
          authorize! :create, @assessment
          if @assessment.save
            render json: { dass_assessment: serialize_for_client(@assessment) },
              status: :created
          else
            render_unprocessable(@assessment)
          end
        end

        # PATCH /api/v1/client/dass_assessments/:id
        # Saves partial draft. Items are individually nullable; the
        # model only requires the assessment_date and validates that
        # any non-nil item value is 0-3.
        def update
          authorize! :update, @assessment
          if @assessment.update(assessment_params)
            render json: { dass_assessment: serialize_for_client(@assessment) }
          else
            render_unprocessable(@assessment)
          end
        end

        # POST /api/v1/client/dass_assessments/:id/submit
        # Submit = sign-and-lock. Updates remaining responses (if
        # any), then calls sign! which sets signed_at and triggers
        # the Signable lock. Scores were computed by the before_save
        # callback during the last update — they're already cached.
        def submit
          authorize! :update, @assessment
          # ActionController::Parameters doesn't have #any? — use the
          # negation of #empty?, which IS defined on the params object.
          unless assessment_params.empty?
            unless @assessment.update(assessment_params)
              return render_unprocessable(@assessment)
            end
          end

          # Validate the questionnaire is complete before signing.
          # Allowing partial submissions would corrupt subscale
          # scoring (sum_items treats nil as 0).
          incomplete = (1..42).reject { |n| @assessment.item(n).present? }
          if incomplete.any?
            return render json: {
              error: {
                code: :incomplete,
                message: "All 42 items must be answered before submitting.",
                details: incomplete.map { |n| "item_#{n}" }
              }
            }, status: :unprocessable_entity
          end

          @assessment.sign!(current_user)
          render json: { dass_assessment: serialize_for_client(@assessment) }
        end

        private

        def ensure_client!
          unless current_user&.role == "client"
            head :forbidden
          end
        end

        def ensure_unsigned
          return unless @assessment&.signed?
          render json: {
            error: { code: :already_signed, message: "This assessment is signed and locked." }
          }, status: :unprocessable_entity
        end

        def current_client_profile
          @current_client_profile ||= current_user.client_profile
        end

        def load_assessment
          @assessment = current_client_profile.dass_assessments.find_by(id: params[:id])
          render_not_found unless @assessment
        end

        # Permit the 42 item columns + the optional appointment link.
        def assessment_params
          item_keys = (1..42).map { |n| :"item_#{n}" }
          params.require(:dass_assessment).permit(*item_keys, :appointment_id)
        end

        # Serialization for the CLIENT view: includes severity bands
        # (so the client gets clinical context) but excludes raw
        # numeric scores (per Q7 — therapist interprets numbers).
        def serialize_for_client(record)
          payload = record.as_json(except: %i[
            depression_score anxiety_score stress_score
          ]).merge(
            signed: record.signed?,
            completed_items: (1..42).count { |n| record.item(n).present? }
          )
          payload
        end

        def render_not_found
          render json: { error: { code: :not_found, message: "Assessment not found" } },
            status: :not_found
        end

        def render_unprocessable(record)
          render json: {
            error: {
              code: :validation_failed,
              message: "Could not save the assessment",
              details: record.errors.full_messages
            }
          }, status: :unprocessable_entity
        end
      end
    end
  end
end
