module Api
  module V1
    module Public
      class BlogPostsController < ApplicationController
        def index
          posts = BlogPost.includes(:author, blog_images: { file_attachment: :blob })
                          .visible_to_public
          render json: { blog_posts: posts.map { |p| card_json(p) } }
        end

        def show
          post = BlogPost.includes(:author, blog_images: { file_attachment: :blob })
                         .find(params[:id])
          unless post.status_published?
            return render json: { error: "Not found", code: "not_found" },
              status: :not_found
          end
          render json: { blog_post: full_json(post) }
        end

        private

        # Card representation: short body excerpt + cover (first image) for
        # the landing/index. Cover lets cards render a header image even
        # though there's no dedicated cover field — the first uploaded
        # image acts as the cover.
        def card_json(p)
          {
            id: p.id,
            title: p.title,
            excerpt: p.body.to_s.lines.first(3).join.strip,
            cover_image_url: cover_image_url_for(p),
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
            status: p.status,
            images: p.blog_images.ordered.map { |img| image_json(img) }
          }
        end

        def author_json(u)
          {
            id: u.id,
            full_name: u.full_name,
            role: u.role
          }
        end

        def cover_image_url_for(p)
          img = p.blog_images.ordered.first
          return nil unless img&.file&.attached?
          Rails.application.routes.url_helpers
            .rails_blob_path(img.file, only_path: true)
        end

        def image_json(img)
          {
            id: img.id,
            alt: img.alt,
            position: img.position,
            url: img.file.attached? ? Rails.application.routes.url_helpers
              .rails_blob_path(img.file, only_path: true) : nil
          }
        end
      end
    end
  end
end
