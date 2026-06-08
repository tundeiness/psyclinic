module Api
  module V1
    module Webhooks
      class StripeController < ApplicationController
        # Webhooks are unauthenticated and CSRF-exempt — Stripe POSTs
        # directly. Authenticity is established by HMAC-SHA256
        # signature verification using the webhook signing secret.
        # In mock mode (no STRIPE_WEBHOOK_SECRET configured) we skip
        # verification — the only callers in that mode are our own
        # dev MockGatewayController.
        skip_before_action :verify_authenticity_token,
          raise: false  # already API mode but defensive

        # POST /api/v1/webhooks/stripe
        def receive
          raw_body = request.raw_post

          unless signature_verified?(raw_body, request.headers["Stripe-Signature"])
            return render json: { error: "Signature verification failed" },
              status: :bad_request
          end

          event =
            begin
              JSON.parse(raw_body)
            rescue JSON::ParserError
              return render json: { error: "Malformed JSON" },
                status: :bad_request
            end

          result = ProcessStripeEvent.call(event)

          if result.success?
            # Always ack 200 — Stripe interprets non-2xx as a retry
            # signal. Including 4xx for events we don't handle would
            # cause infinite retries.
            render json: { received: true, ignored: result.ignored == true },
              status: :ok
          else
            # Internal handling error. 500 lets Stripe retry — usually
            # what we want (transient DB error, etc).
            render json: { error: result.error }, status: :internal_server_error
          end
        end

        private

        # Real Stripe verification: HMAC-SHA256 of the raw body with
        # the webhook secret, compared against the t= timestamp and
        # v1= signature in the Stripe-Signature header.
        #
        # Three modes:
        #  - Production with secret unset: REFUSE all webhooks (loud
        #    misconfiguration; better than silently accepting forged
        #    events).
        #  - Non-production with secret unset: accept (mock mode).
        #  - Any env with secret set: verify HMAC properly. Not
        #    implemented in Phase 5.1; placeholder returns false so
        #    real Stripe traffic to an unimplemented verifier fails
        #    safely until the implementation lands.
        def signature_verified?(_raw_body, _header)
          secret = ENV["STRIPE_WEBHOOK_SECRET"]

          if secret.blank?
            # In production, missing secret = fail closed.
            return false if Rails.env.production?
            return true  # dev/test mock mode
          end

          # TODO(real-stripe): implement HMAC verification per
          # https://stripe.com/docs/webhooks/signatures
          false
        end
      end
    end
  end
end
