require "rails_helper"

RSpec.describe "Avatars & documents", type: :request do
  let(:json) { JSON.parse(response.body) }
  let(:user) { create(:user, :client) }

  def png
    Rack::Test::UploadedFile.new(
      Rails.root.join("spec/fixtures/files/avatar.png"), "image/png"
    )
  end

  def pdf
    Rack::Test::UploadedFile.new(
      Rails.root.join("spec/fixtures/files/doc.pdf"), "application/pdf"
    )
  end

  describe "avatar" do
    it "uploads and then exposes the avatar on the profile" do
      put "/api/v1/me/avatar",
        params: { avatar: png },
        headers: auth_header_for(user)

      expect(response).to have_http_status(:ok)
      expect(user.reload.avatar).to be_attached
      expect(json.dig("user", "avatar", "filename")).to eq("avatar.png")
      expect(json.dig("user", "avatar", "url")).to be_present
    end

    it "rejects an empty avatar request" do
      put "/api/v1/me/avatar", params: {}, headers: auth_header_for(user)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "removes the avatar" do
      user.avatar.attach(png)
      delete "/api/v1/me/avatar", headers: auth_header_for(user)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "documents" do
    it "uploads a document and lists it" do
      post "/api/v1/me/documents",
        params: { document: pdf },
        headers: auth_header_for(user)
      expect(response).to have_http_status(:created)

      get "/api/v1/me/documents", headers: auth_header_for(user)
      expect(response).to have_http_status(:ok)
      expect(json["documents"].size).to eq(1)
      expect(json["documents"].first["filename"]).to eq("doc.pdf")
    end

    it "deletes a document by attachment id" do
      user.documents.attach(pdf)
      attachment_id = user.documents.first.id

      delete "/api/v1/me/documents/#{attachment_id}",
        headers: auth_header_for(user)
      expect(response).to have_http_status(:ok)
      expect(user.reload.documents).to be_empty
    end

    it "404s deleting a non-existent document" do
      delete "/api/v1/me/documents/999999",
        headers: auth_header_for(user)
      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/me/documents"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
