module Api
  module V1
    module Admin
      class SettingsController < BaseController
        before_action :require_real_admin

        SETTING_KEYS = %i[
          flat_rate_cents
          assessment_session_price_cents
          block_full_price_cents
          block_installment_first_pct
          block_installment_second_pct
        ].freeze

        def show
          render json: { settings: serialize_settings(AppSetting.current) }
        end

        def update
          s = AppSetting.current
          permitted = params.require(:settings).permit(*SETTING_KEYS)
          if s.update(permitted)
            render json: { settings: serialize_settings(s) }
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

        def serialize_settings(s)
          {
            flat_rate_cents:                  s.flat_rate_cents,
            assessment_session_price_cents:   s.assessment_session_price_cents,
            block_full_price_cents:           s.block_full_price_cents,
            block_installment_first_pct:      s.block_installment_first_pct,
            block_installment_second_pct:     s.block_installment_second_pct,
            installment_first_amount_cents:   s.installment_first_amount_cents,
            installment_second_amount_cents:  s.installment_second_amount_cents
          }
        end
      end
    end
  end
end
