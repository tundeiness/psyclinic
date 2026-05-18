module Api
  module V1
    class AvatarsController < BaseController
      # PUT /api/v1/me/avatar  (multipart, field: avatar)
      def update
        file = params[:avatar]
        return render_error("No avatar file provided") if file.blank?

        current_user.avatar.attach(file)
        unless current_user.avatar.attached?
          return render_error("Avatar upload failed")
        end

        render json: { user: UserSerializer.call(current_user) }, status: :ok
      end

      # DELETE /api/v1/me/avatar
      def destroy
        current_user.avatar.purge if current_user.avatar.attached?
        render json: { message: "Avatar removed" }, status: :ok
      end
    end
  end
end
