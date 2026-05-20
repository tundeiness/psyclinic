class CreateBlogPosts < ActiveRecord::Migration[7.1]
  def change
    create_table :blog_posts do |t|
      t.references :author, null: false,
        foreign_key: { to_table: :users, on_delete: :cascade }
      t.string  :title, null: false
      t.text    :body,  null: false
      # Markdown is stored raw and rendered safely on read.
      t.integer :status, null: false, default: 0  # draft:0, published:1
      t.datetime :published_at

      t.timestamps
    end

    add_index :blog_posts, %i[status published_at]
  end
end
