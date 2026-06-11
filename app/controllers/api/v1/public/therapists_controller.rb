module Api
  module V1
    module Public
      # Unauthenticated. Lets prospective clients read about therapists
      # before registering or booking. Only approved users with active
      # therapist profiles are listed.
      class TherapistsController < ApplicationController
        def index
          therapists = TherapistProfile
                        .joins(:user)
                        .where(active: true, users: { status: User.statuses[:approved] })
                        .includes(:user, :specializations)
                        .order("users.first_name ASC")

          render json: {
            therapists: therapists.map { |t| public_therapist_json(t) }
          }, status: :ok
        end

        def show
          therapist = TherapistProfile
                        .joins(:user)
                        .where(active: true, users: { status: User.statuses[:approved] })
                        .includes(:user, :specializations)
                        .find(params[:id])

          render json: { therapist: public_therapist_json(therapist) }, status: :ok
        end

        private

        def public_therapist_json(tp)
          # Note: hourly_rate_cents is deliberately omitted from the
          # public payload. Cerca Africa uses uniform clinic-wide
          # pricing (set by admin in AppSetting: assessment_price_cents
          # and block_full_price_cents). Per-therapist rates would
          # mislead clients about what they actually pay. The column
          # still exists on the model — admin-editable for legacy /
          # internal reasons — but it's not shown publicly.
          {
            id: tp.id,
            full_name: tp.full_name,
            headline: tp.headline,
            bio: tp.bio,
            years_experience: tp.years_experience,
            avatar: AttachmentSerializer.one(tp.user.avatar),
            specializations: tp.specializations.map { |s| { id: s.id, name: s.name } }
          }
        end
      end
    end
  end
end
