module Api
  module V1
    module Admin
      class TherapistSpecializationsController < BaseController
        def create
          authorize! :create, TherapistSpecialization
          ts = TherapistSpecialization.new(
            therapist_profile_id: params[:therapist_profile_id],
            specialization_id: params[:specialization_id]
          )
          if ts.save
            render json: { message: "Specialization added to therapist" }, status: :created
          else
            render json: { error: "Invalid", details: ts.errors.full_messages },
              status: :unprocessable_entity
          end
        end

        def destroy
          authorize! :destroy, TherapistSpecialization
          TherapistSpecialization.find(params[:id]).destroy!
          render json: { message: "Specialization removed from therapist" }, status: :ok
        end
      end
    end
  end
end
