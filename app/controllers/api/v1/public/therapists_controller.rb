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
          {
            id: tp.id,
            full_name: tp.full_name,
            headline: tp.headline,
            bio: tp.bio,
            years_experience: tp.years_experience,
            hourly_rate_cents: tp.hourly_rate_cents,
            avatar: AttachmentSerializer.one(tp.user.avatar),
            specializations: tp.specializations.map { |s| { id: s.id, name: s.name } }
          }
        end
      end
    end
  end
end
