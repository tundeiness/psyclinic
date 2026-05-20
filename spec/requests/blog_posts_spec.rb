require "rails_helper"

RSpec.describe "Blog posts", type: :request do
  let(:json) { JSON.parse(response.body) }

  let(:therapist_user) { create(:user, :therapist) }
  let(:other_therapist) { create(:user, :therapist) }
  let(:admin) { create(:user, :admin) }
  let(:client_user) { create(:user, :client) }

  def make_post(author:, **overrides)
    BlogPost.create!(
      author: author,
      title: overrides[:title] || "Coping with anxiety",
      body: overrides[:body] || "# Tips\n\n- Breathing\n- Sleep",
      status: overrides[:status] || :draft
    )
  end

  describe "public read" do
    it "lists only published posts" do
      make_post(author: therapist_user, status: :published)
      make_post(author: therapist_user, title: "Not yet", status: :draft)

      get "/api/v1/public/blog_posts"
      expect(response).to have_http_status(:ok)
      expect(json["blog_posts"].size).to eq(1)
      expect(json["blog_posts"].first["title"]).to eq("Coping with anxiety")
    end

    it "shows a published post by id (no auth)" do
      post = make_post(author: therapist_user, status: :published)
      get "/api/v1/public/blog_posts/#{post.id}"
      expect(response).to have_http_status(:ok)
      expect(json.dig("blog_post", "body")).to match(/Tips/)
    end

    it "404s a draft via the public endpoint" do
      post = make_post(author: therapist_user, status: :draft)
      get "/api/v1/public/blog_posts/#{post.id}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "authoring" do
    it "lets a therapist create a draft post" do
      post "/api/v1/blog_posts",
        params: { blog_post: { title: "Self-care", body: "## Body" } },
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:created)
      expect(json.dig("blog_post", "status")).to eq("draft")
      expect(BlogPost.last.author_id).to eq(therapist_user.id)
    end

    it "stamps published_at when the therapist publishes" do
      p = make_post(author: therapist_user, status: :draft)
      patch "/api/v1/blog_posts/#{p.id}",
        params: { blog_post: { status: "published" } },
        headers: auth_header_for(therapist_user)
      expect(response).to have_http_status(:ok)
      expect(p.reload.published_at).to be_present
    end

    it "forbids a client from creating a post" do
      post "/api/v1/blog_posts",
        params: { blog_post: { title: "X", body: "Y" } },
        headers: auth_header_for(client_user)
      expect(response).to have_http_status(:forbidden)
      expect(BlogPost.count).to eq(0)
    end

    it "forbids one therapist editing another's post" do
      p = make_post(author: therapist_user, status: :published)
      patch "/api/v1/blog_posts/#{p.id}",
        params: { blog_post: { title: "Hijacked" } },
        headers: auth_header_for(other_therapist)
      expect(response).to have_http_status(:forbidden)
      expect(p.reload.title).to eq("Coping with anxiety")
    end
  end

  describe "moderation" do
    it "lets admin edit another therapist's post" do
      p = make_post(author: therapist_user, status: :published,
                    title: "Original")
      patch "/api/v1/blog_posts/#{p.id}",
        params: { blog_post: { title: "Edited by admin" } },
        headers: auth_header_for(admin)
      expect(response).to have_http_status(:ok)
      expect(p.reload.title).to eq("Edited by admin")
    end

    it "lets a co-admin delete a post" do
      tp = other_therapist.therapist_profile
      tp.update!(co_admin: true)
      p = make_post(author: therapist_user, status: :published)
      delete "/api/v1/blog_posts/#{p.id}",
        headers: auth_header_for(other_therapist)
      expect(response).to have_http_status(:ok)
      expect(BlogPost.exists?(p.id)).to be(false)
    end
  end

  describe "authenticated index visibility" do
    it "therapist sees own drafts in their index" do
      make_post(author: therapist_user, status: :draft, title: "Mine")
      make_post(author: other_therapist, status: :published, title: "Theirs")
      get "/api/v1/blog_posts", headers: auth_header_for(therapist_user)
      titles = json["blog_posts"].map { |p| p["title"] }
      expect(titles).to include("Mine")
      expect(titles).not_to include("Theirs")
    end

    it "admin sees every post in the index" do
      make_post(author: therapist_user, status: :draft, title: "T draft")
      make_post(author: other_therapist, status: :published, title: "O pub")
      get "/api/v1/blog_posts", headers: auth_header_for(admin)
      titles = json["blog_posts"].map { |p| p["title"] }
      expect(titles).to include("T draft", "O pub")
    end
  end
end
