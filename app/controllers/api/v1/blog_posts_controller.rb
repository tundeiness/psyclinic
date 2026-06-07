module Api
  module V1
    class BlogPostsController < BaseController
      # GET /api/v1/blog_posts — author's own posts (drafts + published).
      # Admin/co-admin sees everything since they can :manage all posts.
      def index
        scope =
          if current_user.admin? || current_user.co_admin?
            BlogPost.all
          else
            BlogPost.where(author_id: current_user.id)
          end
        posts = scope.includes(:author).by_recent
        render json: { blog_posts: posts.map { |p| post_json(p) } }
      end

      def show
        post = BlogPost.includes(:author).find(params[:id])
        authorize! :read, post
        render json: { blog_post: post_json(post) }
      end

      def create
        authorize! :create, BlogPost
        post = BlogPost.new(post_params.merge(author: current_user))
        if post.save
          render json: { blog_post: post_json(post) }, status: :created
        else
          render_invalid(post)
        end
      end

      def update
        post = BlogPost.find(params[:id])
        authorize! :update, post
        if post.update(post_params)
          render json: { blog_post: post_json(post) }
        else
          render_invalid(post)
        end
      end

      def destroy
        post = BlogPost.find(params[:id])
        authorize! :destroy, post
        post.destroy!
        render json: { message: "Deleted" }
      end

      private

      def post_params
        params.require(:blog_post).permit(:title, :body, :status)
      end

      def post_json(p)
        {
          id: p.id,
          title: p.title,
          body: p.body,
          status: p.status,
          published_at: p.published_at,
          created_at: p.created_at,
          updated_at: p.updated_at,
          author: {
            id: p.author_id,
            full_name: p.author.full_name,
            role: p.author.role
          },
          images: p.blog_images.ordered.map { |img| image_json(img) }
        }
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

      def render_invalid(post)
        render json: {
          error: "Could not save blog post",
          code: "validation_failed",
          details: post.errors.full_messages
        }, status: :unprocessable_entity
      end
    end
  end
end
