class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :phone

      # 0 = client, 1 = therapist, 2 = admin (see User::ROLES)
      t.integer :role, null: false, default: 0

      t.string   :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, :role
  end
end
