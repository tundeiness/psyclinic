require "rails_helper"

RSpec.describe "Admin dashboard widgets", type: :request do
  let(:json) { JSON.parse(response.body) }
  let(:admin) { create(:user, :admin) }

  def appt_for(client, therapist_profile, starts_in:, status: :booked)
    slot = AvailabilitySlot.create!(
      therapist_profile: therapist_profile,
      starts_at: starts_in, ends_at: starts_in + 1.hour, status: :approved
    )
    Appointment.new(
      client_profile: client.client_profile,
      therapist_profile: therapist_profile,
      availability_slot: slot,
      status: status
    ).save!(validate: false)
  end

  describe "bookings_by_day" do
    it "returns a 14-day series, counting non-cancelled appointments" do
      tp = create(:user, :therapist).therapist_profile
      c1 = create(:user, :client)
      c2 = create(:user, :client)

      # Two on the same day, one on a different day, one cancelled (ignored).
      appt_for(c1, tp, starts_in: 3.days.from_now)
      appt_for(c2, tp, starts_in: 3.days.from_now + 2.hours)
      appt_for(c1, tp, starts_in: 5.days.from_now)
      appt_for(c2, tp, starts_in: 6.days.from_now, status: :cancelled)

      get "/api/v1/admin/dashboard", headers: auth_header_for(admin)
      series = json["bookings_by_day"]
      expect(series.size).to eq(14)
      # All future-day buckets should be present in the window.
      # Cancelled appt does NOT count.
      total = series.sum { |d| d["count"] }
      expect(total).to eq(3)
    end
  end

  describe "status_breakdown" do
    it "groups appointment counts by status (human labels)" do
      tp = create(:user, :therapist).therapist_profile
      c = create(:user, :client)
      appt_for(c, tp, starts_in: 1.day.from_now,  status: :booked)
      appt_for(c, tp, starts_in: 2.days.from_now, status: :completed)
      appt_for(c, tp, starts_in: 3.days.from_now, status: :cancelled)

      get "/api/v1/admin/dashboard", headers: auth_header_for(admin)
      bd = json["status_breakdown"]
      expect(bd).to include("booked" => 1, "completed" => 1, "cancelled" => 1)
    end
  end

  describe "top_therapists" do
    it "ranks therapists by non-cancelled session count, top 5" do
      busy = create(:user, :therapist, first_name: "Busy").therapist_profile
      slow = create(:user, :therapist, first_name: "Slow").therapist_profile
      c1 = create(:user, :client)
      c2 = create(:user, :client)

      appt_for(c1, busy, starts_in: 1.day.from_now)
      appt_for(c2, busy, starts_in: 2.days.from_now)
      appt_for(c1, busy, starts_in: 3.days.from_now)
      appt_for(c1, slow, starts_in: 4.days.from_now)

      get "/api/v1/admin/dashboard", headers: auth_header_for(admin)
      ranked = json["top_therapists"]
      expect(ranked.first["full_name"]).to match(/Busy/)
      expect(ranked.first["session_count"]).to eq(3)
      expect(ranked.size).to be <= 5
    end
  end

  describe "counts.blog_posts" do
    it "reports total and published blog post counts" do
      author = create(:user, :therapist)
      BlogPost.create!(author: author, title: "A", body: "x", status: :draft)
      BlogPost.create!(author: author, title: "B", body: "y", status: :published)
      BlogPost.create!(author: author, title: "C", body: "z", status: :published)

      get "/api/v1/admin/dashboard", headers: auth_header_for(admin)
      expect(json.dig("counts", "blog_posts")).to eq(3)
      expect(json.dig("counts", "blog_posts_published")).to eq(2)
    end
  end

  describe "recent_bookings" do
    it "returns the newest 5 non-cancelled appointments, newest first" do
      tp = create(:user, :therapist).therapist_profile
      c  = create(:user, :client)

      # 6 bookings, plus one cancelled (excluded). Created in order so
      # the newest 5 are the last 5 created here.
      6.times do |i|
        appt_for(c, tp, starts_in: (i + 1).days.from_now, status: :booked)
      end
      appt_for(c, tp, starts_in: 12.days.from_now, status: :cancelled)

      get "/api/v1/admin/dashboard", headers: auth_header_for(admin)
      rows = json["recent_bookings"]
      expect(rows.size).to eq(5)
      # Newest-first ordering — the most recently-created appointment
      # should be first.
      expect(rows.first["id"]).to be > rows.last["id"]
      # Cancelled appointments must not appear.
      expect(rows.none? { |r| r["status"] == "cancelled" }).to be(true)
      # Shape check.
      expect(rows.first).to include(
        "id", "client", "therapist", "starts_at", "status", "created_at"
      )
    end
  end

  describe "practice_metrics" do
    it "counts bookings created this month (non-cancelled)" do
      tp = create(:user, :therapist).therapist_profile
      c  = create(:user, :client)

      # 2 created now (this month), 1 cancelled (excluded).
      appt_for(c, tp, starts_in: 2.days.from_now, status: :booked)
      appt_for(c, tp, starts_in: 3.days.from_now, status: :booked)
      appt_for(c, tp, starts_in: 4.days.from_now, status: :cancelled)

      # 1 created last month (excluded by the created_at filter).
      old_slot = AvailabilitySlot.create!(
        therapist_profile: tp,
        starts_at: 5.days.from_now, ends_at: 5.days.from_now + 1.hour,
        status: :approved
      )
      Appointment.new(
        client_profile: c.client_profile,
        therapist_profile: tp,
        availability_slot: old_slot,
        status: :booked
      ).save(validate: false)
      Appointment.last.update_column(:created_at, 35.days.ago)

      get "/api/v1/admin/dashboard", headers: auth_header_for(admin)
      expect(json.dig("practice_metrics", "bookings_this_month")).to eq(2)
    end

    it "averages sessions across THERAPISTS WITH at least one session" do
      busy = create(:user, :therapist).therapist_profile
      slow = create(:user, :therapist).therapist_profile
      create(:user, :therapist) # idle therapist — should be excluded
      c = create(:user, :client)

      # busy: 3 non-cancelled sessions
      3.times do |i|
        appt_for(c, busy, starts_in: (i + 1).days.from_now)
      end
      # slow: 1 session
      appt_for(c, slow, starts_in: 5.days.from_now)

      get "/api/v1/admin/dashboard", headers: auth_header_for(admin)
      # (3 + 1) / 2 active therapists = 2.0 — the idle one doesn't count.
      expect(json.dig("practice_metrics", "avg_sessions_per_active_therapist"))
        .to eq(2.0)
    end

    it "is zero average when no sessions exist anywhere" do
      get "/api/v1/admin/dashboard", headers: auth_header_for(admin)
      expect(json.dig("practice_metrics", "avg_sessions_per_active_therapist"))
        .to eq(0.0)
    end

    it "identifies the top blog author by PUBLISHED post count" do
      prolific = create(:user, :therapist)
      modest   = create(:user, :therapist)

      3.times do |i|
        BlogPost.create!(author: prolific, title: "P#{i}",
                         body: "x", status: :published)
      end
      BlogPost.create!(author: modest, title: "M",
                       body: "y", status: :published)
      # Drafts must not influence the ranking.
      5.times do |i|
        BlogPost.create!(author: modest, title: "MD#{i}",
                         body: "z", status: :draft)
      end

      get "/api/v1/admin/dashboard", headers: auth_header_for(admin)
      top = json.dig("practice_metrics", "top_blog_author")
      expect(top["id"]).to eq(prolific.id)
      expect(top["post_count"]).to eq(3)
    end

    it "top_blog_author is null when nobody has published yet" do
      author = create(:user, :therapist)
      BlogPost.create!(author: author, title: "D",
                       body: "x", status: :draft)

      get "/api/v1/admin/dashboard", headers: auth_header_for(admin)
      expect(json.dig("practice_metrics", "top_blog_author")).to be_nil
    end
  end
end
