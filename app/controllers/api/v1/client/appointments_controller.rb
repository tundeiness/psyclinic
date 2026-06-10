module Api
  module V1
    module Client
      class AppointmentsController < BaseController
        before_action :require_client_profile

        def index
          # v2 Phase 7.1: sweep this client's stale pending_payment
          # appointments before serializing — the list reflects current
          # reality, not stale reservations the user has walked away
          # from.
          ExpireStalePayments.call(client_profile: @cp)
          # Phase 12: also flip any expired booked appointments to
          # :no_show so the client sees the truthful status. Scoped
          # to this client so we don't touch other clients' data.
          SweepNoShows.call(client_profile: @cp)

          appts = Appointment.where(client_profile_id: @cp.id)
                             .includes(:therapist_profile, :availability_slot)
                             .order(created_at: :desc)
          appts.each { |a| authorize! :read, a }
          render json: { appointments: appts.map { |a| AppointmentSerializer.call(a) } }
        end

        def show
          appt = Appointment.find(params[:id])
          authorize! :read, appt
          render json: { appointment: AppointmentSerializer.call(appt) }
        end

        def create
          authorize! :create, Appointment

          result = BookAppointment.call(
            client_profile: @cp,
            availability_slot_id: params[:availability_slot_id],
            reason: params[:reason],
            # v2: client must declare which kind of session this is.
            # Defaults to :assessment for backward compat with older
            # frontend clients — the new frontend will be explicit.
            session_kind: (params[:session_kind].presence || "assessment").to_sym
          )

          if result.success?
            render json: {
              appointment: AppointmentSerializer.call(result.appointment),
              payment: PaymentSerializer.call(result.payment)
            }, status: :created
          else
            render json: { error: result.error }, status: :unprocessable_entity
          end
        end

        # Client cancels their own booked or pending-payment appointment.
        # Phase 12: enforces the 24-hour reschedule rule. Booked
        # appointments within 24 hours of their start time can no
        # longer be cancelled by the client (per Cerca Africa policy).
        # Pending-payment appointments cancel freely since no committed
        # session is being released.
        def destroy
          appt = Appointment.find(params[:id])
          authorize! :destroy, appt

          if appt.booked? && cancellation_too_late?(appt)
            return render json: {
              error: "Sessions can only be cancelled up to 24 hours before " \
                     "the start time. Please contact the clinic if you have " \
                     "an emergency.",
              code: "cancellation_too_late"
            }, status: :unprocessable_entity
          end

          appt.update!(
            status: :cancelled,
            cancellation_reason: params[:cancellation_reason].presence
          )
          render json: { message: "Appointment cancelled" }, status: :ok
        end

        private

        def cancellation_too_late?(appt)
          starts_at = appt.availability_slot&.starts_at
          return false if starts_at.nil?
          starts_at < 24.hours.from_now
        end

        def require_client_profile
          @cp = current_client_profile
          render_error("No client profile", status: :forbidden) if @cp.nil?
        end
      end
    end
  end
end
