module Api
  module V1
    module Admin
      class TherapistsController < BaseController
        def index
          authorize! :read, TherapistProfile
          therapists = TherapistProfile.includes(:user, :specializations).order(created_at: :desc)
          render json: { therapists: therapists.map { |t| TherapistProfileSerializer.call(t) } }
        end

        def show
          tp = TherapistProfile.includes(:user, :specializations).find(params[:id])
          authorize! :read, tp
          render json: { therapist: TherapistProfileSerializer.call(tp) }
        end

        # Admin creates therapist user accounts directly.
        def create
          authorize! :create, TherapistProfile

          user = User.new(therapist_user_params)
          user.role = :therapist

          if user.save
            tp = user.therapist_profile
            tp.update(profile_params) if profile_params.present?
            render json: { therapist: TherapistProfileSerializer.call(tp.reload) }, status: :created
          else
            render json: { error: "Could not create therapist", details: user.errors.full_messages },
              status: :unprocessable_entity
          end
        end

        def destroy
          tp = TherapistProfile.find(params[:id])
          authorize! :destroy, tp
          tp.user.destroy!
          render json: { message: "Therapist removed" }, status: :ok
        end

        private

        def therapist_user_params
          params.require(:therapist).permit(
            :email, :password, :password_confirmation,
            :first_name, :last_name, :phone
          )
        end

        def profile_params
          return {} unless params[:therapist].present?

          params.require(:therapist).permit(:bio, :license_number).to_h
        end
      end
    end
  end
end
