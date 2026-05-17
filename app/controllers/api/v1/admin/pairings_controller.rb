module Api
  module V1
    module Admin
      class PairingsController < BaseController
        def index
          authorize! :read, ClientProfile
          paired = ClientProfile.where.not(therapist_profile_id: nil)
                                .includes(:user, :therapist_profile)
          render json: { pairings: paired.map { |c| ClientProfileSerializer.call(c) } }
        end

        def create
          authorize! :update, ClientProfile

          client = ClientProfile.find(params[:client_profile_id])
          therapist = TherapistProfile.find(params[:therapist_profile_id])

          result = PairClientWithTherapist.call(
            client_profile: client,
            therapist_profile: therapist
          )

          if result.success?
            render json: { client: ClientProfileSerializer.call(result.client_profile) }, status: :ok
          else
            render json: { error: result.error }, status: :unprocessable_entity
          end
        end

        # Unpair: clear the assignment.
        def destroy
          authorize! :update, ClientProfile
          client = ClientProfile.find(params[:id])
          client.update!(therapist_profile_id: nil)
          render json: { message: "Pairing removed" }, status: :ok
        end
      end
    end
  end
end
