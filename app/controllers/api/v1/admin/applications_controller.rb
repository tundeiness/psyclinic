module Api
  module V1
    module Admin
      class ApplicationsController < BaseController
        before_action :load_user, only: %i[approve reject]

        # Pending client/therapist registrations awaiting a decision.
        def index
          authorize! :manage, User
          users = User.where(status: :pending).where.not(role: :admin)
                      .order(created_at: :asc)
          render json: { applications: users.map { |u| application_json(u) } }
        end

        def approve
          authorize! :manage, User
          result = ApproveUser.call(user: @user)
          if result.success?
            render json: { user: application_json(result.user) }, status: :ok
          else
            render json: { error: result.error }, status: :unprocessable_entity
          end
        end

        def reject
          authorize! :manage, User
          result = RejectUser.call(user: @user)
          if result.success?
            render json: { user: application_json(result.user) }, status: :ok
          else
            render json: { error: result.error }, status: :unprocessable_entity
          end
        end

        private

        def load_user
          @user = User.find(params[:id])
        end

        def application_json(u)
          {
            id: u.id,
            email: u.email,
            full_name: u.full_name,
            role: u.role,
            status: u.status,
            created_at: u.created_at
          }
        end
      end
    end
  end
end
