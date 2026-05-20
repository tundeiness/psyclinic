module Api
  module V1
    module Admin
      class DashboardController < BaseController
        def show
          # admin + co-admin only; explicit ability avoids the
          # block-ability class-check leak that resource gates have.
          authorize! :access, :admin_panel

          render json: {
            pending_applications: pending_applications,
            counts: counts,
            payment_inflows: payment_inflows,
            calendar: calendar
          }, status: :ok
        end

        private

        def pending_applications
          User.where(status: :pending).where.not(role: :admin)
              .order(created_at: :asc)
              .map do |u|
            { id: u.id, email: u.email, full_name: u.full_name,
              role: u.role, created_at: u.created_at }
          end
        end

        def counts
          {
            clients: User.where(role: :client).count,
            therapists: User.where(role: :therapist).count,
            pending_applications: User.where(status: :pending)
                                      .where.not(role: :admin).count,
            appointments_upcoming: Appointment.upcoming.count
          }
        end

        def payment_inflows
          succeeded = Payment.where(status: :succeeded)
          {
            total_cents: succeeded.sum(:amount_cents),
            count: succeeded.count,
            recent: succeeded.order(paid_at: :desc).limit(10).map do |p|
              {
                id: p.id,
                amount_cents: p.amount_cents,
                currency: p.currency,
                paid_at: p.paid_at,
                client_profile_id: p.client_profile_id,
                appointment_id: p.appointment_id
              }
            end
          }
        end

        # Therapist availability + booked appointments, optionally scoped
        # to a month via ?month=YYYY-MM (defaults to the current month).
        def calendar
          month = parse_month
          range = month.all_month

          slots = AvailabilitySlot.where(starts_at: range)
                                  .includes(therapist_profile: :user)
          appts = Appointment.joins(:availability_slot)
                              .where(availability_slots: { starts_at: range })
                              .where(status: Appointment::RESERVING_STATUSES)
                              .includes(:client_profile, :therapist_profile, :availability_slot)

          {
            month: month.strftime("%Y-%m"),
            availability: slots.map do |s|
              { id: s.id, therapist: s.therapist_profile.full_name,
                starts_at: s.starts_at, ends_at: s.ends_at, status: s.status }
            end,
            appointments: appts.map do |a|
              { id: a.id, client: a.client_profile.full_name,
                therapist: a.therapist_profile.full_name,
                starts_at: a.availability_slot.starts_at,
                status: a.status }
            end
          }
        end

        def parse_month
          if params[:month].present?
            Date.strptime(params[:month], "%Y-%m")
          else
            Date.current.beginning_of_month
          end
        rescue ArgumentError, Date::Error
          Date.current.beginning_of_month
        end
      end
    end
  end
end
