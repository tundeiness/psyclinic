class ClientContract < ApplicationRecord
  belongs_to :client_profile
  belongs_to :certified_by_user, class_name: "User", optional: true

  has_one_attached :uploaded_document

  enum :signature_method, { electronic: 0, uploaded: 1 }

  validates :contract_version, presence: true
  validates :signed_at,        presence: true

  # Electronic signatures: name must be present.
  validates :electronic_signature_name, presence: true, if: :electronic?

  # Uploaded contracts: file must be attached.
  validate  :uploaded_must_have_attachment, if: :uploaded?

  # An uploaded contract becomes valid only once certified by a
  # therapist or admin. Electronic contracts are valid immediately.
  def valid_for_use?
    electronic? || (uploaded? && certified_at.present?)
  end

  def pending_certification?
    uploaded? && certified_at.nil?
  end

  # Returns the most recent valid contract for this client at the
  # current required version, or nil. Used by PurchaseSessionBlock
  # to gate block purchases.
  def self.current_for(client_profile)
    where(client_profile_id: client_profile.id,
          contract_version: AppSetting.current.current_contract_version)
      .order(signed_at: :desc)
      .detect(&:valid_for_use?)
  end

  private

  def uploaded_must_have_attachment
    errors.add(:uploaded_document, "must be attached") unless uploaded_document.attached?
  end
end
