module Api
  module V1
    module Admin
      class AvailabilitySlotsController < BaseController
        before_action :load_slot, only: %i[update approve reject]

        def index
          authorize! :read, AvailabilitySlot
          slots = AvailabilitySlot.includes(:therapist_profile).order(starts_at: :asc)
          slots = slots.where(status: params[:status]) if params[:status].present?
          render json: { availability_slots: slots.map { |s| AvailabilitySlotSerializer.call(s) } }
        end

        def update
          authorize! :update, @slot
          if @slot.update(slot_params)
            render json: { availability_slot: AvailabilitySlotSerializer.call(@slot) }
          else
            render json: { error: "Invalid", details: @slot.errors.full_messages },
              status: :unprocessable_entity
          end
        end

        def approve
          authorize! :approve, @slot
          @slot.update!(status: :approved)
          render json: { availability_slot: AvailabilitySlotSerializer.call(@slot) }
        end

        def reject
          authorize! :reject, @slot
          @slot.update!(status: :rejected)
          render json: { availability_slot: AvailabilitySlotSerializer.call(@slot) }
        end

        private

        def load_slot
          @slot = AvailabilitySlot.find(params[:id])
        end

        def slot_params
          params.require(:availability_slot).permit(:starts_at, :ends_at, :status)
        end
      end
    end
  end
end
