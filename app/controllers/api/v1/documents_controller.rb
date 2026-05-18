module Api
  module V1
    class DocumentsController < BaseController
      # GET /api/v1/me/documents
      def index
        render json: {
          documents: AttachmentSerializer.many(current_user.documents)
        }, status: :ok
      end

      # POST /api/v1/me/documents  (multipart, field: document OR documents[])
      def create
        files = Array(params[:documents].presence || params[:document]).compact
        return render_error("No document file provided") if files.empty?

        files.each { |f| current_user.documents.attach(f) }
        render json: {
          documents: AttachmentSerializer.many(current_user.documents)
        }, status: :created
      end

      # DELETE /api/v1/me/documents/:id   (:id is the attachment id)
      def destroy
        attachment = current_user.documents.find_by(id: params[:id])
        return render_error("Document not found", status: :not_found) if attachment.nil?

        attachment.purge
        render json: { message: "Document removed" }, status: :ok
      end
    end
  end
end
