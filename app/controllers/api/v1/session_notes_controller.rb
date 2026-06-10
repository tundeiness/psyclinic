module Api
  module V1
    class SessionNotesController < ApplicationController
      before_action :authenticate_user!
      before_action :load_appointment
      before_action :load_or_build_note, except: :create

      # GET /api/v1/appointments/:appointment_id/session_note
      def show
        # Authorize against a placeholder with NO author so the
        # "former therapist can read records they authored" rule
        # doesn't trivially pass for whoever is asking. The real
        # record's author_id is checked only when the record exists.
        authorize! :read, (@note || read_placeholder)
        return render_not_found unless @note
        render json: { session_note: serialize(@note) }
      end

      # POST /api/v1/appointments/:appointment_id/session_note
      def create
        # Pre-fill client_profile_id from the appointment so callers
        # don't have to send it. The form fields below are the
        # narrative content.
        @note = SessionNote.new(note_params.merge(
          appointment: @appointment,
          client_profile_id: @appointment.client_profile_id,
          author: current_user
        ))
        authorize! :create, @note
        if @note.save
          render json: { session_note: serialize(@note) }, status: :created
        else
          render_unprocessable(@note)
        end
      end

      # PATCH /api/v1/appointments/:appointment_id/session_note
      def update
        authorize! :update, (@note || write_placeholder)
        return render_not_found unless @note
        if @note.signed?
          return render json: {
            error: { code: :already_signed, message: "Signed notes are read-only" }
          }, status: :unprocessable_entity
        end
        if @note.update(note_params)
          render json: { session_note: serialize(@note) }
        else
          render_unprocessable(@note)
        end
      end

      # POST /api/v1/appointments/:appointment_id/session_note/sign
      def sign
        authorize! :update, (@note || write_placeholder)
        return render_not_found unless @note
        if @note.signed?
          return render json: {
            error: { code: :already_signed, message: "Already signed" }
          }, status: :unprocessable_entity
        end
        @note.sign!(current_user)
        render json: { session_note: serialize(@note) }
      end

      private

      def read_placeholder
        # Author is nil so the author-match rule cannot accidentally
        # pass for whoever is asking. Only used for authorization.
        SessionNote.new(
          appointment: @appointment,
          client_profile_id: @appointment.client_profile_id,
          author: nil
        )
      end

      def write_placeholder
        SessionNote.new(
          appointment: @appointment,
          client_profile_id: @appointment.client_profile_id,
          author: current_user
        )
      end

      def load_appointment
        @appointment = Appointment.find_by(id: params[:appointment_id])
        render_not_found("Appointment not found") unless @appointment
      end

      def load_or_build_note
        @note = SessionNote.find_by(appointment_id: @appointment.id)
      end

      # The narrative fields plus the optional session metadata
      # (numbers, times). session_date/start_time/end_time can be
      # pre-filled from the appointment slot but are user-editable
      # since the actual session may have started late or run long.
      def note_params
        params.require(:session_note).permit(
          :session_number,
          :session_date,
          :session_start_time,
          :session_end_time,
          :review,
          :addressed_and_plan,
          :clinician_impression
        )
      end

      def serialize(note)
        note.as_json.merge(
          signed: note.signed?,
          signed_at: note.signed_at,
          signed_by_name: note.signed_by&.then { |u| "#{u.first_name} #{u.last_name}" },
          author_name: note.author&.then { |u| "#{u.first_name} #{u.last_name}" },
          appointment: {
            id: @appointment.id,
            client_profile_id: @appointment.client_profile_id,
            therapist_profile_id: @appointment.therapist_profile_id,
            slot_starts_at: @appointment.availability_slot&.starts_at,
            slot_ends_at: @appointment.availability_slot&.ends_at,
            status: @appointment.status
          }
        )
      end

      def render_not_found(message = "Session note not found")
        render json: { error: { code: :not_found, message: message } },
          status: :not_found
      end

      def render_unprocessable(record)
        render json: {
          error: {
            code: :validation_failed,
            message: "Could not save the session note",
            details: record.errors.full_messages
          }
        }, status: :unprocessable_entity
      end
    end
  end
end
