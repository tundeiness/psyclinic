module Api
  module V1
    module Admin
      class SettingsController < BaseController
        before_action :require_real_admin

        def show
          s = AppSetting.current
          render json: { settings: { flat_rate_cents: s.flat_rate_cents } }
        end

        def update
          s = AppSetting.current
          if s.update(flat_rate_cents: params.dig(:settings, :flat_rate_cents))
            render json: { settings: { flat_rate_cents: s.flat_rate_cents } }
          else
            render json: {
              error: "Invalid settings",
              code: "validation_failed",
              details: s.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        private

        # Only a true admin (not a co-admin therapist) may change
        # practice-wide settings.
        def require_real_admin
          return if current_user&.admin?

          render json: { error: "Forbidden", code: "forbidden" },
            status: :forbidden
        end
      end
    end
  end
end
