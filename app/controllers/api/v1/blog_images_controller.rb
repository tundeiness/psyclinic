module Api
  module V1
    class BlogImagesController < BaseController
      before_action :load_post

      # POST /api/v1/blog_posts/:blog_post_id/images
      # multipart, field: file, optional: alt
      def create
        authorize! :update, @post

        image = @post.blog_images.build(alt: params[:alt].to_s)
        image.file.attach(params[:file])
        image.position = (@post.blog_images.maximum(:position) || 0) + 1

        if image.save
          render json: { image: image_json(image) }, status: :created
        else
          render json: {
            error: "Image upload failed",
            code: "validation_failed",
            details: image.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/blog_posts/:blog_post_id/images/:id
      def destroy
        authorize! :update, @post
        image = @post.blog_images.find(params[:id])
        image.destroy!
        render json: { message: "Deleted" }
      end

      private

      def load_post
        @post = BlogPost.find(params[:blog_post_id])
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
