module Api
  module V1
    module Client
      class ContractsController < BaseController
        before_action :require_client_profile

        # GET /api/v1/client/contracts/current
        # Returns the current contract state for this client:
        # - any valid signed contract for the current version
        # - any pending-certification upload
        # - the current required version (for the FE to know what to sign)
        def current
          current_version = AppSetting.current.current_contract_version
          valid = ClientContract.current_for(@cp)
          pending = @cp.client_contracts
            .where(contract_version: current_version, signature_method: :uploaded)
            .where(certified_at: nil)
            .order(signed_at: :desc).first

          render json: {
            current_version: current_version,
            signed_contract: valid && serialize(valid),
            pending_contract: pending && serialize(pending),
            requires_signing: valid.nil? && pending.nil?
          }
        end

        # GET /api/v1/client/contracts/document
        # Streams a personalized PDF copy of the current contract.
        def document
          pdf_data = GenerateClientContract.call(client_profile: @cp)
          send_data pdf_data,
            filename: "cerca-africa-contract-#{@cp.id}.pdf",
            type: "application/pdf",
            disposition: "attachment"
        end

        # POST /api/v1/client/contracts/sign
        # body: { typed_name, sponsor_name?, sponsor_signature_typed? }
        def sign
          result = SignClientContract.call(
            client_profile: @cp,
            typed_name: params[:typed_name],
            sponsor_name: params[:sponsor_name],
            sponsor_signature_typed: params[:sponsor_signature_typed],
            signed_from_ip: request.remote_ip
          )

          if result.success?
            render json: { contract: serialize(result.contract) }, status: :created
          else
            render json: { error: result.error, code: "validation_failed" },
              status: :unprocessable_entity
          end
        end

        # POST /api/v1/client/contracts/upload
        # multipart: { file, sponsor_name? }
        def upload
          result = UploadSignedContract.call(
            client_profile: @cp,
            file: params[:file],
            sponsor_name: params[:sponsor_name]
          )

          if result.success?
            render json: { contract: serialize(result.contract) }, status: :created
          else
            render json: { error: result.error, code: "validation_failed" },
              status: :unprocessable_entity
          end
        end

        private

        def require_client_profile
          @cp = current_user&.client_profile
          render json: { error: "Forbidden", code: "forbidden" },
            status: :forbidden if @cp.nil?
        end

        def serialize(contract)
          {
            id: contract.id,
            contract_version: contract.contract_version,
            signature_method: contract.signature_method,
            signed_at: contract.signed_at,
            valid_for_use: contract.valid_for_use?,
            pending_certification: contract.pending_certification?,
            certified_at: contract.certified_at,
            electronic_signature_name: contract.electronic_signature_name,
            sponsor_name: contract.sponsor_name,
            has_uploaded_document: contract.uploaded_document.attached?
          }
        end
      end
    end
  end
end
