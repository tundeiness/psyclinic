# Records an uploaded signed contract (client downloaded the PDF,
# signed by hand, scanned and uploaded). The resulting ClientContract
# is in pending_certification state until a therapist or admin
# certifies it via CertifyContract.
class UploadSignedContract
  Result = Struct.new(:success?, :contract, :error, keyword_init: true)

  class UploadError < StandardError; end

  ACCEPTED_TYPES = %w[application/pdf image/png image/jpeg].freeze
  MAX_BYTES = 10.megabytes

  def self.call(...) = new(...).call

  def initialize(client_profile:, file:, sponsor_name: nil)
    @client_profile = client_profile
    @file = file
    @sponsor_name = sponsor_name.to_s.strip.presence
  end

  def call
    raise UploadError, "No file provided." if @file.nil?
    validate_file!

    contract = ClientContract.new(
      client_profile: @client_profile,
      contract_version: AppSetting.current.current_contract_version,
      signature_method: :uploaded,
      signed_at: Time.current,  # the timestamp of the UPLOAD, not the
                                # date hand-written on the doc. The
                                # certifier verifies the actual date.
      sponsor_name: @sponsor_name
    )
    contract.uploaded_document.attach(
      io: @file.tempfile,
      filename: @file.original_filename,
      content_type: @file.content_type
    )
    contract.save!

    Result.new(success?: true, contract: contract)
  rescue UploadError => e
    Result.new(success?: false, error: e.message)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message)
  end

  private

  def validate_file!
    unless ACCEPTED_TYPES.include?(@file.content_type)
      raise UploadError,
        "Unsupported file type. Upload a PDF, PNG, or JPEG."
    end
    if @file.size > MAX_BYTES
      raise UploadError, "File is too large (max 10 MB)."
    end
  end
end
