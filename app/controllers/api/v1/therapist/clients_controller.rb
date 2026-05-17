module Api
  module V1
    module Therapist
      class ClientsController < BaseController
        def index
          tp = current_therapist_profile
          return render_error("No therapist profile", status: :forbidden) if tp.nil?

          clients = tp.clients_with_appointments.includes(:user)
          clients.each { |c| authorize! :read, c }
          render json: { clients: clients.map { |c| ClientProfileSerializer.call(c) } }
        end

        def show
          client = ClientProfile.includes(:user).find(params[:id])
          authorize! :read, client
          render json: { client: ClientProfileSerializer.call(client) }
        end
      end
    end
  end
end
