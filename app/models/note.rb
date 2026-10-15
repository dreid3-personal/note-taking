class Note < ApplicationRecord
  # Optimistic locking comes from the lock_version column: saving a stale copy raises
  # ActiveRecord::StaleObjectError instead of overwriting someone else's edit.
  belongs_to :author, class_name: "User"
  belongs_to :folder, optional: true
  has_many :shares, dependent: :destroy

  enum :everyone_access, { none: "none", view: "view", edit: "edit" }, prefix: :everyone, validate: true

  normalizes :title, with: ->(title) { title.strip }
  # Browsers submit textarea line breaks as \r\n but count each as one character for maxlength.
  normalizes :body, with: ->(body) { body.gsub("\r\n", "\n") }

  TITLE_MAX_LENGTH = 200
  BODY_MAX_LENGTH = 100_000

  validates :title, presence: true, length: { maximum: TITLE_MAX_LENGTH }
  validates :body, length: { maximum: BODY_MAX_LENGTH, too_long: ->(note, _) {
    "is too long (#{note.body.length.to_fs(:delimited)} characters; the maximum is #{BODY_MAX_LENGTH.to_fs(:delimited)})"
  } }
end
