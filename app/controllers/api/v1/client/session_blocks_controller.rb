module Api
  module V1
    module Client
      class SessionBlocksController < BaseController
        before_action :require_client_profile

        # GET /api/v1/client/session_blocks
        # Returns the client's blocks (active, completed, forfeited).
        # Mainly used by the dashboard to show "you have N sessions
        # remaining" or "buy a block" depending on state.
        def index
          blocks = @cp.session_blocks.order(purchased_at: :desc)
          render json: { session_blocks: blocks.map { |b| serialize(b) } }
        end

        # POST /api/v1/client/session_blocks
        # body: { payment_mode: "full" }   (installment lands in Phase 7)
        # Initiates a block purchase. Returns the block + payment so the
        # frontend can redirect to the mock checkout.
        def create
          authorize! :create, SessionBlock

          mode = (params[:payment_mode].presence || "full").to_sym
          result = PurchaseSessionBlock.call(
            client_profile: @cp,
            payment_mode: mode
          )

          if result.success?
            render json: {
              session_block: serialize(result.session_block),
              payment: PaymentSerializer.call(result.payment)
            }, status: :created
          else
            render json: {
              error: result.error,
              code: "validation_failed"
            }, status: :unprocessable_entity
          end
        end

        private

        def require_client_profile
          @cp = current_user&.client_profile
          render json: { error: "Forbidden", code: "forbidden" },
            status: :forbidden if @cp.nil?
        end

        def serialize(block)
          {
            id: block.id,
            therapist_profile_id: block.therapist_profile_id,
            therapist_name: block.therapist_profile&.full_name,
            purchased_at: block.purchased_at,
            sessions_total: block.sessions_total,
            sessions_used: block.sessions_used,
            sessions_remaining: block.sessions_remaining,
            payment_mode: block.payment_mode,
            status: block.status,
            installment_due: block.installment_due?,
            # Up-front payment status — the booking flow gates on
            # this being :succeeded before letting the client book
            # normal sessions against the block.
            first_payment_status: block.first_payment&.status
          }
        end
      end
    end
  end
end
