module Api
  module V1
    module Admin
      # All admin endpoints require the admin panel ability, which only
      # a true admin or a co-admin (flagged therapist) has. This single
      # gate avoids relying on resource abilities that use blocks (which
      # CanCanCan treats permissively at the class level).
      class BaseController < Api::V1::BaseController
        before_action :require_admin_panel

        private

        def require_admin_panel
          return if current_user && can?(:access, :admin_panel)

          render json: { error: "Forbidden", code: "forbidden" },
            status: :forbidden
        end
      end
    end
  end
end
