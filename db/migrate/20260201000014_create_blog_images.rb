class CreateBlogImages < ActiveRecord::Migration[7.1]
  def change
    create_table :blog_images do |t|
      t.references :blog_post, null: false,
        foreign_key: { on_delete: :cascade }
      t.string :alt, default: ""
      # Ordering for "first image becomes the card cover": stable insertion order.
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :blog_images, %i[blog_post_id position]
  end
end
