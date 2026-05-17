module Api
  module V1
    module Admin
      class ClientsController < BaseController
        def index
          authorize! :read, ClientProfile
          clients = ClientProfile.includes(:user, :therapist_profile).order(created_at: :desc)
          render json: { clients: clients.map { |c| ClientProfileSerializer.call(c) } }
        end

        def show
          client = ClientProfile.includes(:user, :therapist_profile).find(params[:id])
          authorize! :read, client
          render json: { client: ClientProfileSerializer.call(client) }
        end

        # Removing a client removes the underlying user (cascade) too.
        def destroy
          client = ClientProfile.find(params[:id])
          authorize! :destroy, client
          client.user.destroy!
          render json: { message: "Client removed" }, status: :ok
        end
      end
    end
  end
end
