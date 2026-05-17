module Api
  module V1
    module Client
      class AvailabilitySlotsController < BaseController
        # A client only ever sees approved, unbooked, future slots —
        # and only for the therapist they are paired with.
        def index
          cp = current_client_profile
          return render_error("No client profile", status: :forbidden) if cp.nil?

          unless cp.paired?
            return render json: { availability_slots: [], message: "You are not yet paired with a therapist" }
          end

          slots = AvailabilitySlot.bookable.for_therapist(cp.therapist_profile_id)
                                  .includes(:therapist_profile)
                                  .order(starts_at: :asc)
          slots.each { |s| authorize! :read, s }
          render json: { availability_slots: slots.map { |s| AvailabilitySlotSerializer.call(s) } }
        end
      end
    end
  end
end
