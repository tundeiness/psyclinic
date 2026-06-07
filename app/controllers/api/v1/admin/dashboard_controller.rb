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
            calendar: calendar,
            bookings_by_day: bookings_by_day,
            status_breakdown: status_breakdown,
            top_therapists: top_therapists,
            recent_bookings: recent_bookings,
            practice_metrics: practice_metrics
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
            appointments_upcoming: Appointment.upcoming.count,
            blog_posts: BlogPost.count,
            blog_posts_published: BlogPost.status_published.count
          }
        end

        # Bookings per day across a 14-day window centered on today:
        # the previous 7 days, today, and the next 6 days. Gives admins
        # both recent activity context and upcoming load. Empty days
        # included so the x-axis is continuous.
        def bookings_by_day
          days = 14
          start_day = Date.current - 7.days
          range = start_day.beginning_of_day..(start_day + (days - 1).days).end_of_day

          counts_by_day = Appointment
            .joins(:availability_slot)
            .where(availability_slots: { starts_at: range })
            .where.not(status: :cancelled)
            .group("DATE(availability_slots.starts_at)")
            .count

          (0...days).map do |i|
            d = start_day + i.days
            { date: d.iso8601, count: counts_by_day[d] || 0 }
          end
        end

        # Appointment counts grouped by status across the whole table.
        # Useful for a status-breakdown donut.
        def status_breakdown
          Appointment.group(:status).count.transform_keys do |k|
            # `group(:status)` returns the enum integer; map it back to
            # the human-readable label.
            Appointment.statuses.key(k) || k.to_s
          end
        end

        # Top therapists by booked-or-completed session count. Limit to 5
        # for the leaderboard widget.
        def top_therapists
          TherapistProfile
            .joins(:appointments)
            .where.not(appointments: { status: :cancelled })
            .group("therapist_profiles.id")
            .order(Arel.sql("COUNT(appointments.id) DESC"))
            .limit(5)
            .includes(:user)
            .map do |tp|
              {
                id: tp.id,
                full_name: tp.full_name,
                session_count: tp.appointments
                                 .where.not(status: :cancelled).count
              }
            end
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

        # Three quick practice-wide metrics for the dashboard:
        # - bookings_this_month: appointments CREATED in the current
        #   calendar month (booking velocity, not session date)
        # - avg_sessions_per_active_therapist: total non-cancelled
        #   sessions / therapists who have at least one. Excludes idle
        #   therapists so the figure stays meaningful.
        # - top_blog_author: the author with the most PUBLISHED posts
        #   (drafts are excluded since they aren't visible publicly).
        def practice_metrics
          month_range =
            Date.current.beginning_of_month.beginning_of_day..
            Date.current.end_of_month.end_of_day

          bookings_this_month = Appointment
            .where(created_at: month_range)
            .where.not(status: :cancelled)
            .count

          non_cancelled_sessions = Appointment.where.not(status: :cancelled)
          active_count = non_cancelled_sessions
            .distinct.count(:therapist_profile_id)

          avg = active_count.zero? ? 0.0 :
            (non_cancelled_sessions.count.to_f / active_count).round(2)

          top_author_row = BlogPost
            .status_published
            .group(:author_id)
            .order(Arel.sql("COUNT(*) DESC"))
            .limit(1)
            .count
          # `top_author_row` is { author_id => count }; expand to a user
          # row if any author has at least one published post.
          top_blog_author =
            if top_author_row.any?
              author_id, count = top_author_row.first
              u = User.find(author_id)
              { id: u.id, full_name: u.full_name, post_count: count }
            end

          {
            bookings_this_month: bookings_this_month,
            avg_sessions_per_active_therapist: avg,
            top_blog_author: top_blog_author
          }
        end

        # Newest 5 non-cancelled appointments for the dashboard table.
        def recent_bookings
          Appointment
            .where.not(status: :cancelled)
            .includes(:client_profile, :therapist_profile, :availability_slot)
            .order(created_at: :desc)
            .limit(5)
            .map do |a|
              {
                id: a.id,
                client: a.client_profile.full_name,
                therapist: a.therapist_profile.full_name,
                starts_at: a.availability_slot.starts_at,
                status: a.status,
                created_at: a.created_at
              }
            end
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
