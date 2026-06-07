class WheelOfLifeAssessment < ApplicationRecord
  include Signable

  belongs_to :client_profile
  belongs_to :appointment, optional: true
  belongs_to :author, class_name: "User"

  # 9 life areas. Each value is the number of 1-10 Likert items in
  # that area. The PDF form differs in item count per area: 5 in
  # Career/Health/Friends, 4 in the rest.
  AREAS = {
    "career"             => 5,
    "fun_and_recreation" => 4,
    "money_and_finances" => 4,
    "physical_environment" => 4,
    "personal_growth"    => 4,
    "health_and_wellbeing" => 5,
    "friends"            => 5,
    "family"             => 4,
    "significant_other"  => 4
  }.freeze

  validates :assessment_date, presence: true
  validate  :scores_have_valid_shape

  # Compute area totals + percentages on save.
  before_save :compute_totals

  # Returns total raw score for a given area (sum of its items).
  def total_for(area)
    items = (scores || {})[area] || []
    items.sum { |v| v.to_i }
  end

  # Returns percentage (0-100) for a given area.
  def percentage_for(area)
    return 0 unless AREAS.key?(area)
    max = AREAS[area] * 10
    return 0 if max.zero?
    ((total_for(area).to_f / max) * 100).round
  end

  private

  def scores_have_valid_shape
    return if scores.blank?

    unless scores.is_a?(Hash)
      errors.add(:scores, "must be a hash keyed by area name")
      return
    end

    scores.each do |area, items|
      unless AREAS.key?(area)
        errors.add(:scores, "unknown area '#{area}'")
        next
      end
      unless items.is_a?(Array) && items.size == AREAS[area]
        errors.add(:scores,
          "area '#{area}' must be an array of #{AREAS[area]} values")
        next
      end
      items.each do |v|
        next if v.nil? # allow partial completion before signing
        unless v.is_a?(Integer) && (1..10).cover?(v)
          errors.add(:scores,
            "area '#{area}' has out-of-range value #{v.inspect}")
        end
      end
    end
  end

  def compute_totals
    self.totals = AREAS.keys.each_with_object({}) do |area, h|
      h[area] = {
        "total"      => total_for(area),
        "max"        => AREAS[area] * 10,
        "percentage" => percentage_for(area)
      }
    end
  end
end
