class User < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :teams, through: :memberships
  has_many :shares, dependent: :destroy
  has_many :authored_folders, class_name: "Folder", foreign_key: :author_id, inverse_of: :author
  has_many :authored_notes, class_name: "Note", foreign_key: :author_id, inverse_of: :author

  normalizes :name, with: ->(name) { name.strip }
  normalizes :email, with: ->(email) { email.strip.downcase }

  NAME_MAX_LENGTH = 100
  EMAIL_MAX_LENGTH = 254

  validates :name, presence: true, length: { maximum: NAME_MAX_LENGTH }
  validates :email, presence: true, length: { maximum: EMAIL_MAX_LENGTH }, uniqueness: { case_sensitive: false }
end
