module Api
  module V1
    module Public
      # Read-only public access to the practice's pricing.
      # Authenticated or not — clients use this on the buy-block page
      # so they can see the price before committing. No editable
      # fields exposed (those live on /api/v1/admin/settings).
      class PricingController < ApplicationController
        def show
          s = AppSetting.current
          render json: {
            pricing: {
              assessment_session_price_cents:  s.assessment_session_price_cents,
              block_full_price_cents:          s.block_full_price_cents,
              block_installment_first_pct:     s.block_installment_first_pct,
              block_installment_second_pct:    s.block_installment_second_pct,
              installment_first_amount_cents:  s.installment_first_amount_cents,
              installment_second_amount_cents: s.installment_second_amount_cents
            }
          }
        end
      end
    end
  end
end
