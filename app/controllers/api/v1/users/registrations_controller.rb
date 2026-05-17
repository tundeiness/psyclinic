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
            notify_pending(resource)
            render json: {
              message: "Signed up successfully. Your account is pending admin approval.",
              user: UserSerializer.call(resource)
            }, status: :created
          else
            render json: {
              error: "Sign up failed",
              details: resource.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        def notify_pending(user)
          # Admins are auto-approved and skip the pending workflow.
          return if user.admin?

          Notify.call(
            user: user,
            kind: "application_pending",
            title: "Your application is pending review",
            body: "An administrator will review your account shortly."
          )
          UserMailer.application_pending(user).deliver_later
        end
      end
    end
  end
end
