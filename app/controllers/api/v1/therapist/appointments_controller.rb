module Api
  module V1
    module Therapist
      class AppointmentsController < BaseController
        before_action :require_therapist_profile

        def index
          # Phase 12: auto-flip booked appointments past their end-time-
          # plus-grace-period to :no_show before serializing. Therapist
          # gets up-to-date status without needing a background job.
          SweepNoShows.call(therapist_profile: @tp)

          appts = Appointment.where(therapist_profile_id: @tp.id)
                             .includes(:client_profile, :availability_slot)
                             .order(created_at: :desc)
          appts.each { |a| authorize! :read, a }
          render json: { appointments: appts.map { |a| AppointmentSerializer.call(a) } }
        end

        def show
          appt = Appointment.find(params[:id])
          authorize! :read, appt
          render json: { appointment: AppointmentSerializer.call(appt) }
        end

        # Therapist marks an appointment completed/cancelled.
        def update
          appt = Appointment.find(params[:id])
          authorize! :update, appt
          if appt.update(appointment_params)
            render json: { appointment: AppointmentSerializer.call(appt) }
          else
            render json: { error: "Invalid", details: appt.errors.full_messages },
              status: :unprocessable_entity
          end
        end

        private

        def require_therapist_profile
          @tp = current_therapist_profile
          render_error("No therapist profile", status: :forbidden) if @tp.nil?
        end

        def appointment_params
          params.require(:appointment).permit(:status)
        end
      end
    end
  end
end
