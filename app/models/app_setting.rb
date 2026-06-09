# Singleton settings row. Use AppSetting.current to read/write the one
# practice-wide configuration record (created on first access).
class AppSetting < ApplicationRecord
  validates :flat_rate_cents,
    numericality: { greater_than_or_equal_to: 0, only_integer: true }

  # v2 pricing keys, all in kobo.
  validates :assessment_session_price_cents,
    numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :block_full_price_cents,
    numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :block_installment_first_pct,
    numericality: { greater_than_or_equal_to: 0,
                    less_than_or_equal_to: 100,
                    only_integer: true }
  validates :block_installment_second_pct,
    numericality: { greater_than_or_equal_to: 0,
                    less_than_or_equal_to: 100,
                    only_integer: true }
  validate :installment_pcts_sum_to_100

  validates :pending_payment_expiry_minutes,
    numericality: { greater_than: 0, only_integer: true }

  def self.current
    first || create!(flat_rate_cents: 0)
  end

  # Derived kobo amounts for the two installments. The second part
  # is a simple percentage of the block price; the first part is
  # whatever remains so the two sum exactly to the full price (no
  # rounding gap).
  def installment_first_amount_cents
    block_full_price_cents - installment_second_amount_cents
  end

  def installment_second_amount_cents
    (block_full_price_cents * block_installment_second_pct) / 100
  end

  private

  def installment_pcts_sum_to_100
    return if block_installment_first_pct.to_i +
              block_installment_second_pct.to_i == 100
    errors.add(:base, "installment percentages must sum to 100")
  end
end
