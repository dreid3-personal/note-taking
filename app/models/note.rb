class Note < ApplicationRecord
  # Optimistic locking comes from the lock_version column: saving a stale copy raises
  # ActiveRecord::StaleObjectError instead of overwriting someone else's edit.
  belongs_to :author, class_name: "User"
  belongs_to :folder, optional: true
  has_many :shares, dependent: :destroy

  enum :everyone_access, { none: "none", view: "view", edit: "edit" }, prefix: :everyone, validate: true

  normalizes :title, with: ->(title) { title.strip }

  validates :title, presence: true
end
