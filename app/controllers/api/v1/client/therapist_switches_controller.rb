module Api
  module V1
    module Client
      class TherapistSwitchesController < BaseController
        before_action :require_client_profile

        # POST /api/v1/client/therapist_switches
        # body: { to_therapist_profile_id, reason? }
        def create
          to_tp = TherapistProfile.find_by(id: params[:to_therapist_profile_id])
          unless to_tp
            return render json: {
              error: "Therapist not found",
              code: "not_found"
            }, status: :not_found
          end

          result = SwitchTherapist.call(
            client_profile: @cp,
            new_therapist: to_tp,
            reason: params[:reason]
          )

          if result.success?
            render json: {
              assignment: serialize(result.assignment),
              forfeited_block_id: result.forfeited_block&.id,
              forfeited_sessions_count:
                result.forfeited_block&.sessions_remaining || 0
            }, status: :created
          else
            render json: {
              error: result.error,
              code: result.code.to_s
            }, status: :unprocessable_entity
          end
        end

        # GET /api/v1/client/therapist_switches/preview?to_therapist_profile_id=N
        # Returns a description of what the switch would forfeit so
        # the FE can show a confirmation modal with concrete numbers.
        def preview
          to_tp = TherapistProfile.find_by(id: params[:to_therapist_profile_id])
          unless to_tp
            return render json: {
              error: "Therapist not found",
              code: "not_found"
            }, status: :not_found
          end

          current_tp = @cp.current_therapist
          same = current_tp&.id == to_tp.id

          # Count what would be forfeited if they proceed.
          active_block = @cp.session_blocks
            .where(therapist_profile_id: current_tp&.id, status: :active)
            .where("sessions_used < sessions_total")
            .first
          unused = active_block&.sessions_remaining || 0

          pending_count = @cp.appointments
            .where(status: %i[booked pending_payment])
            .joins(:availability_slot)
            .where("availability_slots.starts_at > ?", Time.current)
            .count

          render json: {
            current_therapist: current_tp && {
              id: current_tp.id,
              full_name: current_tp.full_name
            },
            new_therapist: { id: to_tp.id, full_name: to_tp.full_name },
            same_therapist: same,
            forfeited_sessions_count: unused,
            pending_appointments_count: pending_count,
            can_switch: !same && pending_count.zero?,
            block_status: active_block && {
              id: active_block.id,
              sessions_remaining: unused,
              payment_mode: active_block.payment_mode
            }
          }
        end

        private

        def require_client_profile
          @cp = current_user&.client_profile
          render json: { error: "Forbidden", code: "forbidden" },
            status: :forbidden if @cp.nil?
        end

        def serialize(a)
          {
            id: a.id,
            from_therapist_id: a.from_therapist_id,
            to_therapist_id: a.to_therapist_id,
            started_at: a.started_at,
            ended_at: a.ended_at,
            forfeited_block_id: a.forfeited_block_id,
            forfeited_sessions_count: a.forfeited_sessions_count,
            reason: a.reason
          }
        end
      end
    end
  end
end
