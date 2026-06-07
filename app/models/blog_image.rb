class BlogImage < ApplicationRecord
  belongs_to :blog_post

  has_one_attached :file

  validates :file, presence: true
  validate  :file_within_limits

  scope :ordered, -> { order(:position, :id) }

  ALLOWED_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  MAX_BYTES     = 5.megabytes

  private

  def file_within_limits
    return unless file.attached?

    unless ALLOWED_TYPES.include?(file.content_type)
      errors.add(:file, "must be a JPG, PNG, GIF, or WebP")
    end

    if file.byte_size > MAX_BYTES
      errors.add(:file, "must be under 5 MB")
    end
  end
end
