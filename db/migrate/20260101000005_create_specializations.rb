class CreateSpecializations < ActiveRecord::Migration[7.1]
  def change
    create_table :specializations do |t|
      t.string :name, null: false
      t.text :description

      t.timestamps
    end
    add_index :specializations, :name, unique: true

    create_table :therapist_specializations do |t|
      t.references :therapist_profile, null: false, foreign_key: { on_delete: :cascade }
      t.references :specialization, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :therapist_specializations,
      %i[therapist_profile_id specialization_id],
      unique: true,
      name: "idx_unique_therapist_specialization"
  end
end
