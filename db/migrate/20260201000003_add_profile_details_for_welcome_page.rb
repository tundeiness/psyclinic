class AddProfileDetailsForWelcomePage < ActiveRecord::Migration[7.1]
  def change
    # Richer therapist info so clients can "read about therapists" before
    # booking (welcome page). bio/license_number already exist on
    # therapist_profiles from the original migration; add the rest.
    add_column :therapist_profiles, :headline, :string
    add_column :therapist_profiles, :years_experience, :integer
    add_column :therapist_profiles, :hourly_rate_cents, :integer, null: false, default: 0
  end
end
