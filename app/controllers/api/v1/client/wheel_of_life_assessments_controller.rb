module Api
  module V1
    module Client
      # Phase 18.1: client-facing Wheel of Life endpoints. The client
      # is the author. Unlike DASS, this is a reflective self-coaching
      # tool, not a validated clinical instrument — so per the Phase 18
      # brief Q3, the client SEES their own scores and percentages
      # after submission (vs DASS where raw numbers are hidden).
      class WheelOfLifeAssessmentsController < ApplicationController
        before_action :authenticate_user!
        before_action :ensure_client!
        before_action :load_assessment, only: %i[show update submit]
        before_action :ensure_unsigned, only: %i[update submit]

        # GET /api/v1/client/wheel_of_life_assessments
        def index
          records = current_client_profile.wheel_of_life_assessments
            .order(created_at: :desc)
          render json: {
            wheel_of_life_assessments: records.map { |r| serialize(r) }
          }
        end

        # GET /api/v1/client/wheel_of_life_assessments/:id
        def show
          authorize! :read, @assessment
          render json: { wheel_of_life_assessment: serialize(@assessment) }
        end

        # POST /api/v1/client/wheel_of_life_assessments
        def create
          @assessment = WheelOfLifeAssessment.new(
            client_profile: current_client_profile,
            author: current_user,
            assessment_date: Date.current,
            scores: empty_scores_skeleton
          )
          authorize! :create, @assessment
          if @assessment.save
            render json: { wheel_of_life_assessment: serialize(@assessment) },
              status: :created
          else
            render_unprocessable(@assessment)
          end
        end

        # PATCH /api/v1/client/wheel_of_life_assessments/:id
        # Accepts partial updates to scores (per-area arrays) and any
        # of the four reflection text fields. Merges into existing
        # scores so the client can save progressively.
        def update
          authorize! :update, @assessment
          merged = merge_score_patch(@assessment.scores, params_scores)
          attrs = reflection_params.to_h.merge(scores: merged)
          if @assessment.update(attrs)
            render json: { wheel_of_life_assessment: serialize(@assessment) }
          else
            render_unprocessable(@assessment)
          end
        end

        # POST /api/v1/client/wheel_of_life_assessments/:id/submit
        # Validates that every item in every area is filled, then signs.
        def submit
          authorize! :update, @assessment

          # Apply any final patch before validating completeness.
          merged = merge_score_patch(@assessment.scores, params_scores)
          attrs = reflection_params.to_h.merge(scores: merged)
          unless @assessment.update(attrs)
            return render_unprocessable(@assessment)
          end

          missing = incomplete_areas(@assessment.scores)
          if missing.any?
            return render json: {
              error: {
                code: :incomplete,
                message: "Every item in every area must be answered before submitting.",
                details: missing
              }
            }, status: :unprocessable_entity
          end

          @assessment.sign!(current_user)
          render json: { wheel_of_life_assessment: serialize(@assessment) }
        end

        private

        def ensure_client!
          head :forbidden unless current_user&.role == "client"
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
          @assessment = current_client_profile.wheel_of_life_assessments.find_by(id: params[:id])
          render_not_found unless @assessment
        end

        # Returns a hash matching WheelOfLifeAssessment::AREAS with
        # arrays of nils. Used to initialize a new draft so the JSON
        # always has the right shape regardless of how the FE patches.
        def empty_scores_skeleton
          WheelOfLifeAssessment::AREAS.each_with_object({}) do |(area, count), h|
            h[area] = Array.new(count) # array of nils
          end
        end

        # The FE sends a patch like:
        #   { scores: { "career" => [8, null, 7, null, null], ... } }
        # We merge it into the existing scores so unprovided areas /
        # items are preserved. Within an area, the FE sends the full
        # array (not a sparse map), so we overwrite per-area.
        def merge_score_patch(existing, patch)
          base = (existing || empty_scores_skeleton).deep_dup
          return base unless patch.is_a?(Hash) || patch.respond_to?(:to_unsafe_h)
          patch_hash = patch.respond_to?(:to_unsafe_h) ? patch.to_unsafe_h : patch
          patch_hash.each do |area, items|
            next unless WheelOfLifeAssessment::AREAS.key?(area.to_s)
            next unless items.is_a?(Array)
            count = WheelOfLifeAssessment::AREAS[area.to_s]
            normalized = Array.new(count) do |i|
              v = items[i]
              # Coerce empty-string / "null" to nil so the model
              # validation passes; coerce numeric strings to ints.
              if v.nil? || v == "" || v == "null"
                nil
              else
                begin
                  Integer(v)
                rescue ArgumentError, TypeError
                  v # let the model validation fail with a clear msg
                end
              end
            end
            base[area.to_s] = normalized
          end
          base
        end

        def params_scores
          params.dig(:wheel_of_life_assessment, :scores) || {}
        end

        def reflection_params
          params.fetch(:wheel_of_life_assessment, {}).permit(
            :focus_area, :current_state, :whats_missing, :what_to_create
          )
        end

        # Returns a list of "area:index" strings for items still nil.
        # Empty list means complete.
        def incomplete_areas(scores)
          missing = []
          WheelOfLifeAssessment::AREAS.each do |area, count|
            items = (scores || {})[area] || []
            (0...count).each do |i|
              missing << "#{area}[#{i}]" if items[i].nil?
            end
          end
          missing
        end

        def serialize(record)
          record.as_json.merge(
            signed: record.signed?,
            signed_at: record.signed_at
          )
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
