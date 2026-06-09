module Api
  module V1
    module Dev
      # Dev-only mock checkout simulator. Mounted only in non-production
      # environments (see config/routes.rb). The frontend's mock
      # checkout page calls this with outcome: "succeed" or "fail"; we
      # synthesize a Stripe-shaped event and dispatch it through the
      # same ProcessStripeEvent service that real Stripe webhooks use.
      #
      # This is the development equivalent of a Stripe customer
      # completing 3DS, the card succeeding or failing, and Stripe
      # firing the webhook. The flow exercises the production code
      # path; only the gateway-to-controller hop is different.
      class MockGatewayController < ApplicationController
        # POST /api/v1/dev/mock_gateway/:payment_intent_id/simulate
        # body: { outcome: "succeed" | "fail" }
        #
        # Note: param is named `outcome` not `action` because `action`
        # is a Rails-reserved param overwritten by routing with the
        # controller action name. Don't trip over this.
        def simulate
          if Rails.env.production?
            return render json: { error: "Not available in production" },
              status: :not_found
          end

          intent_id = params[:payment_intent_id]
          outcome_param = params[:outcome].to_s

          payment = Payment.find_by(provider_reference: intent_id)
          unless payment
            return render json: { error: "Payment intent not found" },
              status: :not_found
          end

          outcome =
            case outcome_param
            when "succeed" then :succeeded
            when "fail"    then :failed
            else
              return render json: { error: "outcome must be 'succeed' or 'fail'" },
                status: :bad_request
            end

          gateway = PaymentGateways::MockStripe.new
          event = gateway.build_event(
            payment_intent_id: intent_id,
            outcome: outcome,
            amount_cents: payment.amount_cents
          )

          result = ProcessStripeEvent.call(event)

          # The simulator's HTTP status reflects whether the SIMULATION
          # was processed, not whether the payment succeeded. A "fail"
          # outcome is a legitimate, expected result — return 200 with
          # the resulting state in the body. Only return 422 if the
          # event-processing pipeline itself errored (e.g., DB
          # constraint violation while writing the result).
          dispatch_ok = result.success? || result.ignored || result.payment.present?

          if dispatch_ok
            payment.reload
            payable = payment.payable
            render json: {
              simulated: outcome_param,
              payment_status: payment.status,
              # Only one of these will be present depending on payable
              # type. The frontend uses payable_type to route post-
              # checkout (booking-confirmed page vs block-purchased
              # page).
              payable_type: payment.payable_type,
              appointment_status: payable.is_a?(Appointment) ? payable.reload.status : nil,
              session_block_id: payable.is_a?(SessionBlock) ? payable.id : nil
            }
          else
            render json: { error: result.error, payment_status: payment.reload.status },
              status: :unprocessable_entity
          end
        end
      end
    end
  end
end
