module Api
  module V1
    module Users
      class RegistrationsController < Devise::RegistrationsController
        respond_to :json

        private

        def sign_up_params
          params.require(:user).permit(
            :email, :password, :password_confirmation,
            :first_name, :last_name, :phone, :role
          )
        end

        def respond_with(resource, _opts = {})
          if resource.persisted?
            render json: {
              message: "Signed up successfully",
              user: UserSerializer.call(resource)
            }, status: :created
          else
            render json: {
              error: "Sign up failed",
              details: resource.errors.full_messages
            }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
