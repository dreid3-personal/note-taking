class Folder < ApplicationRecord
  belongs_to :author, class_name: "User"
  belongs_to :parent, class_name: "Folder", optional: true
  belongs_to :team, optional: true
  has_many :subfolders, class_name: "Folder", foreign_key: :parent_id, inverse_of: :parent
  has_many :notes
  has_many :shares, dependent: :destroy

  # Whether a folder is a team folder is fixed when it is created.
  attr_readonly :team_id

  enum :everyone_access, { none: "none", view: "view", edit: "edit" }, prefix: :everyone, validate: true

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true
  validate :not_inside_itself, if: :parent_id_changed?
  validate :team_folder_stays_put, if: :team_folder?

  before_destroy :ensure_deletable, prepend: true

  def team_folder?
    team_id.present?
  end

  # The folders above this one, nearest first.
  def ancestors
    parent ? [ parent, *parent.ancestors ] : []
  end

  private
    def not_inside_itself
      return unless persisted? && parent

      if parent == self || parent.ancestors.include?(self)
        errors.add(:parent, "can't be the folder itself or one of its subfolders")
      end
    end

    def team_folder_stays_put
      errors.add(:base, "A team folder can't be moved.") if parent_id.present?
      errors.add(:name, "of a team folder changes only with the team") if name != team&.name
      errors.add(:everyone_access, "can't be changed on a team folder") unless everyone_none?
    end

    def ensure_deletable
      if team_folder?
        errors.add(:base, "A team folder can't be deleted.")
      elsif subfolders.exists? || notes.exists?
        errors.add(:base, "Move or delete everything inside this folder first.")
      end
      throw :abort if errors.any?
    end
end
