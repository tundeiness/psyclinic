module Api
  module V1
    module Admin
      class ClientsController < BaseController
        # Access is gated by Admin::BaseController#require_admin_panel
        # (admin or co-admin only), so per-action resource checks are
        # unnecessary here.
        def index
          clients = ClientProfile.includes(:user).order(created_at: :desc)
          render json: { clients: clients.map { |c| ClientProfileSerializer.call(c) } }
        end

        def show
          client = ClientProfile.includes(:user).find(params[:id])
          render json: { client: ClientProfileSerializer.call(client) }
        end

        # Removing a client removes the underlying user (cascade) too.
        def destroy
          client = ClientProfile.find(params[:id])
          client.user.destroy!
          render json: { message: "Client removed" }, status: :ok
        end
      end
    end
  end
end
