class DassAssessment < ApplicationRecord
  include Signable

  belongs_to :client_profile
  belongs_to :appointment, optional: true
  belongs_to :author, class_name: "User"

  # DASS-42 subscale composition (Lovibond & Lovibond, 1995).
  # NOTE: DASS-42 sums items directly. The ×2 multiplier belongs to
  # the 21-item short form, not the 42-item long form.
  DEPRESSION_ITEMS = [3, 5, 10, 13, 16, 17, 21, 24, 26, 31, 34, 37, 38, 42].freeze
  ANXIETY_ITEMS    = [2, 4, 7, 9, 15, 19, 20, 23, 25, 28, 30, 36, 40, 41].freeze
  STRESS_ITEMS     = [1, 6, 8, 11, 12, 14, 18, 22, 27, 29, 32, 33, 35, 39].freeze

  # Published DASS-42 severity cutoffs.
  SEVERITY_THRESHOLDS = {
    depression: [
      [0,   9,  "normal"],
      [10,  13, "mild"],
      [14,  20, "moderate"],
      [21,  27, "severe"],
      [28,  Float::INFINITY, "extremely_severe"]
    ],
    anxiety: [
      [0,   7,  "normal"],
      [8,   9,  "mild"],
      [10,  14, "moderate"],
      [15,  19, "severe"],
      [20,  Float::INFINITY, "extremely_severe"]
    ],
    stress: [
      [0,   14, "normal"],
      [15,  18, "mild"],
      [19,  25, "moderate"],
      [26,  33, "severe"],
      [34,  Float::INFINITY, "extremely_severe"]
    ]
  }.freeze

  validates :assessment_date, presence: true
  validate :items_within_likert_range

  # Compute and cache subscale scores + severity labels whenever the
  # record is saved.
  before_save :compute_scores

  def item(n)
    public_send("item_#{n}")
  end

  private

  def items_within_likert_range
    (1..42).each do |n|
      v = public_send("item_#{n}")
      next if v.nil? # allow partial completion before signing
      unless (0..3).cover?(v)
        errors.add(:"item_#{n}", "must be 0-3")
      end
    end
  end

  def compute_scores
    self.depression_score = sum_items(DEPRESSION_ITEMS)
    self.anxiety_score    = sum_items(ANXIETY_ITEMS)
    self.stress_score     = sum_items(STRESS_ITEMS)

    self.depression_severity = severity_for(:depression, depression_score)
    self.anxiety_severity    = severity_for(:anxiety,    anxiety_score)
    self.stress_severity     = severity_for(:stress,     stress_score)
  end

  def sum_items(item_numbers)
    item_numbers.sum { |n| public_send("item_#{n}").to_i }
  end

  def severity_for(scale, score)
    return nil if score.nil?
    SEVERITY_THRESHOLDS[scale].each do |min, max, label|
      return label if score.between?(min, max)
    end
    nil
  end
end
