class Share < ApplicationRecord
  belongs_to :folder, optional: true
  belongs_to :note, optional: true
  belongs_to :user, optional: true
  belongs_to :team, optional: true

  enum :access, { view: "view", edit: "edit" }, validate: true

  validate :exactly_one_item
  validate :exactly_one_grantee
  validate :not_a_team_folder
  validates :user_id, uniqueness: { scope: [ :note_id, :folder_id ], message: "already has a share for this item" }, allow_nil: true
  validates :team_id, uniqueness: { scope: [ :note_id, :folder_id ], message: "already has a share for this item" }, allow_nil: true

  # The note or folder being shared.
  def item
    note || folder
  end

  # The user or team it is shared with.
  def grantee
    user || team
  end

  private
    def exactly_one_item
      errors.add(:base, "Share exactly one note or folder") unless note_id.present? ^ folder_id.present?
    end

    def exactly_one_grantee
      errors.add(:base, "Share with exactly one user or team") unless user_id.present? ^ team_id.present?
    end

    def not_a_team_folder
      errors.add(:folder, "is a team folder, which can't be shared") if folder&.team_folder?
    end
end
