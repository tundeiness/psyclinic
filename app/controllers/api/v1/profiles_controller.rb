module Api
  module V1
    class ProfilesController < BaseController
      def me
        render json: { user: UserSerializer.call(current_user) }, status: :ok
      end
    end
  end
end
