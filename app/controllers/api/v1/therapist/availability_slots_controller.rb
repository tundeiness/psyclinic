module Api
  module V1
    module Therapist
      class AvailabilitySlotsController < BaseController
        before_action :require_therapist_profile
        before_action :load_slot, only: %i[update destroy]

        def index
          slots = AvailabilitySlot.for_therapist(@tp.id).order(starts_at: :asc)
          render json: { availability_slots: slots.map { |s| AvailabilitySlotSerializer.call(s) } }
        end

        def create
          slot = AvailabilitySlot.new(slot_params)
          slot.therapist_profile_id = @tp.id
          authorize! :create, slot

          if slot.save
            render json: { availability_slot: AvailabilitySlotSerializer.call(slot) }, status: :created
          else
            render json: { error: "Invalid", details: slot.errors.full_messages },
              status: :unprocessable_entity
          end
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

        def destroy
          authorize! :destroy, @slot
          if @slot.appointment.present? && !@slot.appointment.cancelled?
            return render_error("Cannot delete a slot with an active booking")
          end

          @slot.destroy!
          render json: { message: "Slot removed" }, status: :ok
        end

        private

        def require_therapist_profile
          @tp = current_therapist_profile
          render_error("No therapist profile", status: :forbidden) if @tp.nil?
        end

        def load_slot
          @slot = AvailabilitySlot.for_therapist(@tp.id).find(params[:id])
        end

        def slot_params
          params.require(:availability_slot).permit(:starts_at, :ends_at)
        end
      end
    end
  end
end
