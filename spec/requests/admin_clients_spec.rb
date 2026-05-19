require "rails_helper"

RSpec.describe "Admin clients listing", type: :request do
  let(:json) { JSON.parse(response.body) }

  it "lists clients for an admin (no dead pairing association)" do
    admin = create(:user, :admin)
    create(:user, :client)
    create(:user, :client)

    get "/api/v1/admin/clients", headers: auth_header_for(admin)

    expect(response).to have_http_status(:ok)
    expect(json["clients"]).to be_an(Array)
    expect(json["clients"].size).to be >= 2
    expect(json["clients"].first).to include("id", "user")
  end

  it "forbids a non-admin" do
    client = create(:user, :client)
    get "/api/v1/admin/clients", headers: auth_header_for(client)
    expect(response).to have_http_status(:forbidden)
  end
end
