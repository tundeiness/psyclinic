module Api
  module V1
    module Admin
      class SpecializationsController < BaseController
        def index
          authorize! :read, Specialization
          render json: { specializations: Specialization.order(:name).map { |s| spec_json(s) } }
        end

        def create
          authorize! :create, Specialization
          spec = Specialization.new(spec_params)
          if spec.save
            render json: { specialization: spec_json(spec) }, status: :created
          else
            render json: { error: "Invalid", details: spec.errors.full_messages },
              status: :unprocessable_entity
          end
        end

        def destroy
          authorize! :destroy, Specialization
          Specialization.find(params[:id]).destroy!
          render json: { message: "Specialization removed" }, status: :ok
        end

        private

        def spec_params
          params.require(:specialization).permit(:name, :description)
        end

        def spec_json(s)
          { id: s.id, name: s.name, description: s.description }
        end
      end
    end
  end
end
