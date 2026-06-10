module Api
  module V1
    module Staff
      class ContractsController < BaseController
        before_action :require_admin_or_therapist

        # GET /api/v1/admin/contracts/pending
        # Lists uploaded contracts awaiting certification, oldest first
        # (so the queue is FIFO).
        def pending
          contracts = ClientContract.uploaded
            .where(certified_at: nil)
            .includes(client_profile: :user)
            .order(signed_at: :asc)
          render json: {
            contracts: contracts.map { |c| serialize(c) }
          }
        end

        # POST /api/v1/admin/contracts/:id/certify
        def certify
          contract = ClientContract.find(params[:id])
          result = CertifyContract.call(
            contract: contract,
            certifier: current_user
          )
          if result.success?
            render json: { contract: serialize(result.contract) }
          else
            render json: { error: result.error, code: "validation_failed" },
              status: :unprocessable_entity
          end
        end

        # GET /api/v1/admin/contracts/:id/document
        # Streams the uploaded file so the certifier can view it.
        def document
          contract = ClientContract.find(params[:id])
          unless contract.uploaded_document.attached?
            return render json: { error: "No document attached" },
              status: :not_found
          end
          send_data contract.uploaded_document.download,
            filename: contract.uploaded_document.filename.to_s,
            type: contract.uploaded_document.content_type,
            disposition: "inline"
        end

        private

        def require_admin_or_therapist
          unless current_user&.admin? || current_user&.therapist?
            render json: { error: "Forbidden", code: "forbidden" },
              status: :forbidden
          end
        end

        def serialize(contract)
          cp = contract.client_profile
          {
            id: contract.id,
            client_profile_id: cp.id,
            client_name: cp.full_name,
            client_email: cp.user&.email,
            contract_version: contract.contract_version,
            signature_method: contract.signature_method,
            signed_at: contract.signed_at,
            certified_at: contract.certified_at,
            certified_by_user_id: contract.certified_by_user_id,
            sponsor_name: contract.sponsor_name,
            has_uploaded_document: contract.uploaded_document.attached?,
            pending_certification: contract.pending_certification?
          }
        end
      end
    end
  end
end
