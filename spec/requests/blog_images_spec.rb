require "rails_helper"

RSpec.describe "Blog images", type: :request do
  let(:json) { JSON.parse(response.body) }
  let(:therapist) { create(:user, :therapist) }
  let(:other_therapist) { create(:user, :therapist) }
  let(:admin) { create(:user, :admin) }
  let(:client_user) { create(:user, :client) }
  let(:post_obj) {
    BlogPost.create!(author: therapist, title: "T",
                     body: "B", status: :draft)
  }

  # Minimal valid PNG (1×1, transparent) for Active Storage uploads. Using
  # Rack::Test::UploadedFile keeps this independent of RSpec/Rails harness
  # variation across versions.
  PNG_1X1 = [
    "89504E470D0A1A0A0000000D49484452000000010000000108020000009077",
    "53DE0000000C49444154789C636060000000000400015A2D02220000000049",
    "454E44AE426082"
  ].join.scan(/../).map(&:hex).pack("C*").freeze

  def png_fixture
    file = Tempfile.new(["fixture", ".png"])
    file.binmode
    file.write(PNG_1X1)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/png")
  end

  # Build an image, attach the file BEFORE saving so the presence
  # validation on :file is satisfied. The controller does the same — see
  # BlogImagesController#create.
  def create_image(post, alt: "x")
    img = post.blog_images.build(alt: alt)
    img.file.attach(png_fixture)
    img.save!
    img
  end

  describe "POST images" do
    it "lets the author upload an image to their post" do
      post "/api/v1/blog_posts/#{post_obj.id}/images",
        params: { file: png_fixture, alt: "Demo" },
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:created)
      expect(json.dig("image", "alt")).to eq("Demo")
      expect(json.dig("image", "url")).to be_present
      expect(post_obj.blog_images.count).to eq(1)
    end

    it "forbids a different therapist from uploading to someone else's post" do
      post "/api/v1/blog_posts/#{post_obj.id}/images",
        params: { file: png_fixture },
        headers: auth_header_for(other_therapist)
      expect(response).to have_http_status(:forbidden)
      expect(post_obj.blog_images.count).to eq(0)
    end

    it "lets the admin upload to ANY post (moderation)" do
      post "/api/v1/blog_posts/#{post_obj.id}/images",
        params: { file: png_fixture },
        headers: auth_header_for(admin)
      expect(response).to have_http_status(:created)
    end

    it "forbids clients entirely" do
      post "/api/v1/blog_posts/#{post_obj.id}/images",
        params: { file: png_fixture },
        headers: auth_header_for(client_user)
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects when no file is sent" do
      post "/api/v1/blog_posts/#{post_obj.id}/images",
        params: { alt: "no file" },
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE images" do
    it "lets the author delete their own image" do
      img = create_image(post_obj)
      delete "/api/v1/blog_posts/#{post_obj.id}/images/#{img.id}",
        headers: auth_header_for(therapist)
      expect(response).to have_http_status(:ok)
      expect(post_obj.blog_images.exists?(img.id)).to be(false)
    end

    it "cascades when the post itself is destroyed" do
      create_image(post_obj)
      expect {
        post_obj.destroy!
      }.to change { BlogImage.count }.by(-1)
    end
  end

  describe "serialization" do
    it "exposes the first image as cover_image_url in the public index" do
      published = BlogPost.create!(author: therapist, title: "Pub",
                                   body: "B", status: :published)
      create_image(published, alt: "c")

      get "/api/v1/public/blog_posts"
      card = json["blog_posts"].find { |b| b["id"] == published.id }
      expect(card["cover_image_url"]).to be_present
    end

    it "returns null cover_image_url when no images uploaded" do
      published = BlogPost.create!(author: therapist, title: "Pub",
                                   body: "B", status: :published)

      get "/api/v1/public/blog_posts"
      card = json["blog_posts"].find { |b| b["id"] == published.id }
      expect(card["cover_image_url"]).to be_nil
    end
  end
end
