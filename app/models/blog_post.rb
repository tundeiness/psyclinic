class BlogPost < ApplicationRecord
  belongs_to :author, class_name: "User"
  has_many :blog_images, dependent: :destroy

  # Stored as Markdown; rendered safely on the frontend.
  enum :status, { draft: 0, published: 1 }, prefix: true

  validates :title, presence: true, length: { maximum: 200 }
  validates :body,  presence: true, length: { maximum: 50_000 }

  scope :visible_to_public, -> { status_published.order(published_at: :desc) }
  scope :by_recent,         -> { order(updated_at: :desc) }

  # Set published_at the first time status moves to "published".
  before_save :stamp_published_at

  private

  def stamp_published_at
    if status_published? && published_at.blank?
      self.published_at = Time.current
    end
  end
end
