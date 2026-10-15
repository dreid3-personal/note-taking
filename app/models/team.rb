class Team < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :shares, dependent: :destroy
  has_one :folder, inverse_of: :team

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  after_update :rename_folder, if: :saved_change_to_name?

  # Creates the team, its team folder and the creator's membership, all or nothing.
  # Returns the team; if anything failed, it is unsaved and carries the errors.
  def self.create_with_folder(name:, creator:)
    team = new(name: name)
    transaction do
      team.save!
      team.create_folder!(name: team.name, author: creator)
      team.memberships.create!(user: creator)
    end
    team
  rescue ActiveRecord::RecordInvalid => error
    unless error.record == team
      error.record.errors.full_messages.each { |message| team.errors.add(:base, message) }
    end
    team
  end

  private
    def rename_folder
      folder&.update!(name: name)
    end
end
