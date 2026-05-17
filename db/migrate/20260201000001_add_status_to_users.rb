class AddStatusToUsers < ActiveRecord::Migration[7.1]
  def change
    # Account approval workflow. 0 = pending (default for self-signup
    # clients/therapists), 1 = approved, 2 = rejected. Admins are created
    # already approved (handled in the model / seeds).
    add_column :users, :status, :integer, null: false, default: 0
    add_index  :users, :status

    # Backfill: any pre-existing users (e.g. seeded admin/therapist/client
    # from the previous iteration) are treated as approved so we don't
    # lock anyone out on migrate.
    reversible do |dir|
      dir.up { execute "UPDATE users SET status = 1" }
    end
  end
end
