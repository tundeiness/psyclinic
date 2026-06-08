require "rails_helper"

RSpec.describe "Co-admin, flat rate & v2 pricing", type: :request do
  let(:json) { JSON.parse(response.body) }

  let(:admin)          { create(:user, :admin) }
  let(:therapist_user) { create(:user, :therapist) }
  let(:tp)             { therapist_user.therapist_profile }
  let(:client_user)    { create(:user, :client) }
  let(:cp)             { client_user.client_profile }

  def slot(starts_in)
    AvailabilitySlot.create!(
      therapist_profile: tp,
      starts_at: starts_in, ends_at: starts_in + 1.hour, status: :approved
    )
  end

  describe "v2 assessment session pricing" do
    before do
      AppSetting.current.update!(
        assessment_session_price_cents: 5_000_000  # ₦50,000 in kobo
      )
    end

    it "charges the assessment session price for an assessment booking" do
      r = BookAppointment.call(
        client_profile: cp,
        availability_slot_id: slot(2.days.from_now).id,
        session_kind: :assessment
      )
      expect(r.success?).to be(true)
      expect(r.payment.amount_cents).to eq(5_000_000)
    end

    it "rejects a normal booking before block purchasing lands" do
      # Phase 5.1: normal sessions require a SessionBlock which Phase 6
      # introduces. Booking a :normal session must fail cleanly with
      # a helpful error rather than silently fall back to legacy
      # flat-rate pricing.
      r = BookAppointment.call(
        client_profile: cp,
        availability_slot_id: slot(2.days.from_now).id,
        session_kind: :normal
      )
      expect(r.success?).to be(false)
      expect(r.error).to match(/active session block/i)
    end
  end

  describe "flat rate settings endpoint" do
    it "lets a real admin set the flat rate" do
      patch "/api/v1/admin/settings",
        params: { settings: { flat_rate_cents: 12000 } },
        headers: auth_header_for(admin)
      expect(response).to have_http_status(:ok)
      expect(AppSetting.current.flat_rate_cents).to eq(12000)
    end

    it "forbids a co-admin from changing settings" do
      tp.update!(co_admin: true)
      patch "/api/v1/admin/settings",
        params: { settings: { flat_rate_cents: 999 } },
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "co-admin promotion (admin only)" do
    it "lets the admin promote a therapist to co-admin" do
      patch "/api/v1/admin/therapists/#{tp.id}/promote_co_admin",
        headers: auth_header_for(admin)
      expect(response).to have_http_status(:ok)
      expect(tp.reload.co_admin).to be(true)
    end

    it "lets the admin demote a co-admin" do
      tp.update!(co_admin: true)
      patch "/api/v1/admin/therapists/#{tp.id}/demote_co_admin",
        headers: auth_header_for(admin)
      expect(response).to have_http_status(:ok)
      expect(tp.reload.co_admin).to be(false)
    end

    it "forbids a co-admin from promoting another therapist" do
      tp.update!(co_admin: true)
      other = create(:user, :therapist).therapist_profile
      patch "/api/v1/admin/therapists/#{other.id}/promote_co_admin",
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:forbidden)
      expect(other.reload.co_admin).to be(false)
    end
  end

  describe "co-admin powers" do
    before { tp.update!(co_admin: true) }

    it "can list clients (admin-like power)" do
      create(:user, :client)
      get "/api/v1/admin/clients", headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:ok)
    end

    it "can review pending applications" do
      create(:user, :client, :pending)
      get "/api/v1/admin/applications",
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:ok)
    end

    it "still cannot change practice settings" do
      patch "/api/v1/admin/settings",
        params: { settings: { flat_rate_cents: 1 } },
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
