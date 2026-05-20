class AddCoAdminToTherapistProfiles < ActiveRecord::Migration[7.1]
  def change
    add_column :therapist_profiles, :co_admin, :boolean,
      null: false, default: false
    add_index :therapist_profiles, :co_admin
  end
end
