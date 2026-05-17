class CreateTherapistProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :therapist_profiles do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.text :bio
      t.string :license_number
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end
