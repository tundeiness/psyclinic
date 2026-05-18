module Api
  module V1
    module Client
      class PaymentsController < BaseController
        before_action :require_client_profile

        def show
          payment = Payment.find(params[:id])
          return forbid unless owns?(payment)

          render json: { payment: PaymentSerializer.call(payment) }
        end

        # Confirms a pending payment. In the real Stripe flow a webhook
        # calls the equivalent of ConfirmPayment; here the client triggers
        # it after completing the (simulated) intent. Pass
        # force_failure=true to exercise the failure path.
        def confirm
          payment = Payment.find(params[:id])
          return forbid unless owns?(payment)

          result = ConfirmPayment.call(
            payment: payment,
            gateway_params: { force_failure: ActiveModel::Type::Boolean.new.cast(params[:force_failure]) }
          )

          if result.success?
            render json: {
              payment: PaymentSerializer.call(result.payment),
              appointment: AppointmentSerializer.call(result.appointment)
            }, status: :ok
          else
            render json: {
              error: result.error,
              payment: PaymentSerializer.call(result.payment)
            }, status: :unprocessable_entity
          end
        end

        private

        def require_client_profile
          @cp = current_client_profile
          render_error("No client profile", status: :forbidden) if @cp.nil?
        end

        def owns?(payment)
          payment.client_profile_id == @cp&.id
        end

        def forbid
          render json: { error: "Forbidden" }, status: :forbidden
        end
      end
    end
  end
end
