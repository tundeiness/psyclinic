module Api
  module V1
    module Client
      class AppointmentsController < BaseController
        before_action :require_client_profile

        def index
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
            reason: params[:reason]
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

        # Client cancels their own booked appointment.
        def destroy
          appt = Appointment.find(params[:id])
          authorize! :destroy, appt
          appt.cancel!
          render json: { message: "Appointment cancelled" }, status: :ok
        end

        private

        def require_client_profile
          @cp = current_client_profile
          render_error("No client profile", status: :forbidden) if @cp.nil?
        end
      end
    end
  end
end
