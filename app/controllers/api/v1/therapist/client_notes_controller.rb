module Api
  module V1
    module Therapist
      class ClientNotesController < BaseController
        before_action :load_therapist
        before_action :load_client

        # GET /api/v1/therapist/clients/:client_id/notes
        def index
          notes = ClientNote
                    .where(therapist_profile_id: @tp.id,
                           client_profile_id: @client.id)
                    .recent
          render json: { notes: notes.map { |n| note_json(n) } }
        end

        # POST /api/v1/therapist/clients/:client_id/notes
        def create
          note = ClientNote.new(
            therapist_profile_id: @tp.id,
            client_profile_id: @client.id,
            body: params.dig(:note, :body)
          )
          authorize! :create, note

          if note.save
            render json: { note: note_json(note) }, status: :created
          else
            render json: {
              error: "Could not save note",
              code: "validation_failed",
              details: note.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        private

        def load_therapist
          @tp = current_therapist_profile
          return if @tp

          render_error("No therapist profile", status: :forbidden)
        end

        def load_client
          return if performed? # therapist check already rendered

          @client = ClientProfile.find(params[:client_id])
          return if @tp.has_client?(@client.id)

          render json: { error: "Forbidden", code: "forbidden" },
            status: :forbidden
        end

        def note_json(note)
          {
            id: note.id,
            body: note.body,
            created_at: note.created_at,
            client_profile_id: note.client_profile_id
          }
        end
      end
    end
  end
end
