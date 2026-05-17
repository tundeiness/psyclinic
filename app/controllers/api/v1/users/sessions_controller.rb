module Api
  module V1
    module Users
      class SessionsController < Devise::SessionsController
        respond_to :json

        private

        def respond_with(resource, _opts = {})
          render json: {
            message: "Logged in",
            user: UserSerializer.call(resource)
          }, status: :ok
        end

        def respond_to_on_destroy
          if current_user
            render json: { message: "Logged out" }, status: :ok
          else
            render json: { error: "No active session" }, status: :unauthorized
          end
        end
      end
    end
  end
end
