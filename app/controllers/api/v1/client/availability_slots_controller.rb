module Api
  module V1
    module Client
      class AvailabilitySlotsController < BaseController
        # Clients browse ALL approved, unbooked, future slots across every
        # approved therapist. Optional filters support the calendar /
        # monthly view: ?therapist_profile_id=, ?date=YYYY-MM-DD,
        # ?month=YYYY-MM.
        def index
          cp = current_client_profile
          return render_error("No client profile", status: :forbidden) if cp.nil?

          # v2 Phase 7.1: sweep stale pending_payment appointments
          # before listing slots so that abandoned reservations don't
          # appear booked. Costs ~a single DB query per call.
          ExpireStalePayments.call

          slots = AvailabilitySlot.bookable
                                  .includes(therapist_profile: :user)
                                  .order(starts_at: :asc)

          if params[:therapist_profile_id].present?
            slots = slots.for_therapist(params[:therapist_profile_id])
          end

          if params[:date].present?
            day = Date.parse(params[:date])
            slots = slots.where(starts_at: day.all_day)
          elsif params[:month].present?
            start_of_month = Date.strptime(params[:month], "%Y-%m")
            slots = slots.where(starts_at: start_of_month.all_month)
          end

          slots.each { |s| authorize! :read, s }
          render json: { availability_slots: slots.map { |s| AvailabilitySlotSerializer.call(s) } }
        rescue ArgumentError, Date::Error
          render_error("Invalid date or month format", status: :unprocessable_entity)
        end
      end
    end
  end
end
