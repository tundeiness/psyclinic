require "rails_helper"

RSpec.describe "Co-admin, flat rate & first-free pricing", type: :request do
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

  describe "first-ever appointment is free, then flat rate" do
    before { AppSetting.current.update!(flat_rate_cents: 8000) }

    it "charges 0 for the client's first booking" do
      r = BookAppointment.call(
        client_profile: cp, availability_slot_id: slot(2.days.from_now).id
      )
      expect(r.success?).to be(true)
      expect(r.payment.amount_cents).to eq(0)
    end

    it "charges the flat rate on the second booking" do
      first = BookAppointment.call(
        client_profile: cp, availability_slot_id: slot(2.days.from_now).id
      )
      ConfirmPayment.call(payment: first.payment)

      second = BookAppointment.call(
        client_profile: cp, availability_slot_id: slot(3.days.from_now).id
      )
      expect(second.success?).to be(true)
      expect(second.payment.amount_cents).to eq(8000)
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
