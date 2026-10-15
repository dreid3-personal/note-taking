class CreateFolders < ActiveRecord::Migration[8.1]
  def change
    create_table :folders do |t|
      t.string :name, null: false
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.references :parent, foreign_key: { to_table: :folders }
      t.references :team, foreign_key: true, index: { unique: true }
      t.string :everyone_access, null: false, default: "none"

      t.timestamps

      t.check_constraint "everyone_access IN ('none', 'view', 'edit')", name: "folders_everyone_access_check"
      t.check_constraint "team_id IS NULL OR parent_id IS NULL", name: "folders_team_folder_top_level_check"
    end
  end
end
