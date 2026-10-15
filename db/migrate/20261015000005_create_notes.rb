class CreateNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :notes do |t|
      t.string :title, null: false
      t.text :body, null: false, default: ""
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.references :folder, foreign_key: true
      t.string :everyone_access, null: false, default: "none"
      t.integer :lock_version, null: false, default: 0

      t.timestamps

      t.check_constraint "everyone_access IN ('none', 'view', 'edit')", name: "notes_everyone_access_check"
    end
  end
end
