# Singleton settings row. Use AppSetting.current to read/write the one
# practice-wide configuration record (created on first access).
class AppSetting < ApplicationRecord
  validates :flat_rate_cents,
    numericality: { greater_than_or_equal_to: 0, only_integer: true }

  def self.current
    first || create!(flat_rate_cents: 0)
  end
end
