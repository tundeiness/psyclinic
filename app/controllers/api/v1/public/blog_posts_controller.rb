module Api
  module V1
    module Public
      class BlogPostsController < ApplicationController
        def index
          posts = BlogPost.includes(:author).visible_to_public
          render json: { blog_posts: posts.map { |p| card_json(p) } }
        end

        def show
          post = BlogPost.includes(:author).find(params[:id])
          unless post.status_published?
            return render json: { error: "Not found", code: "not_found" },
              status: :not_found
          end
          render json: { blog_post: full_json(post) }
        end

        private

        # Card representation: short body excerpt for the landing/index.
        def card_json(p)
          {
            id: p.id,
            title: p.title,
            excerpt: p.body.to_s.lines.first(3).join.strip,
            author: author_json(p.author),
            published_at: p.published_at
          }
        end

        def full_json(p)
          {
            id: p.id,
            title: p.title,
            body: p.body, # raw Markdown; frontend renders safely
            author: author_json(p.author),
            published_at: p.published_at,
            status: p.status
          }
        end

        def author_json(u)
          {
            id: u.id,
            full_name: u.full_name,
            role: u.role
          }
        end
      end
    end
  end
end
