# A note's or folder's sharing settings: everyone_access (changed with PATCH on the item), its
# shares, and the access it inherits from the folders above it. Only the item's author may see or
# change them, and never for a team folder. The item always comes from the database: the one in
# the path, or the share's own note or folder.
class Api::SharesController < Api::BaseController
  before_action :set_item, only: %i[index create]
  before_action :set_share, only: %i[update destroy]
  before_action -> { require_author!(@item) }

  def index
    render json: {
      everyone_access: @item.everyone_access,
      shares: @item.shares.includes(:user, :team).order(:id).map { |share| share_json(share) },
      inherited: visible_inherited_grants(@item).map { |grant| grant_json(grant) }
    }
  end

  # Shares the item with a user, found by email (case and spaces don't matter), or a team.
  def create
    sent = scalar_params(:email, :team_id, :access)
    share = @item.shares.new(access: sent[:access], user: find_user(sent[:email]), team: find_team(sent[:team_id]))

    if sent[:email].present? == sent[:team_id].present?
      share.errors.add(:base, "Send either an email or a team_id")
    elsif sent[:email].present? && share.user.nil?
      share.errors.add(:email, "doesn't match any user")
    elsif sent[:team_id].present? && share.team.nil?
      share.errors.add(:team_id, "doesn't match any team")
    elsif share.user == @item.author
      share.errors.add(:email, "is the author's, who already has access")
    end

    if share.errors.empty? && share.save
      render json: share_json(share), status: :created, location: api_share_url(share)
    else
      render json: { errors: share.errors.to_hash }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    # Two quick requests can both pass the uniqueness validation; the unique index stops the second.
    render json: { errors: { base: [ "That user or team already has a share for this item" ] } }, status: :unprocessable_entity
  end

  def update
    if @share.update(access: scalar_params(:access).fetch(:access) { raise BadRequest })
      render json: share_json(@share)
    else
      render_errors(@share)
    end
  end

  def destroy
    @share.destroy!
    head :no_content
  end

  private
    def set_item
      @item = params[:note_id] ? find_record(Note, params[:note_id]) : find_record(Folder, params[:folder_id])
    end

    def set_share
      @share = find_record(Share, params[:id])
      @item = @share.item
    end

    def find_user(email)
      User.find_by(email: email.to_s) if email.present?
    end

    def find_team(id)
      Team.find_by(id: id) if id.to_s.match?(/\A\d+\z/)
    end

    def share_json(share)
      {
        id: share.id, access: share.access, note_id: share.note_id, folder_id: share.folder_id,
        user: (user_json(share.user) if share.user), team: ({ id: share.team.id, name: share.team.name } if share.team)
      }
    end

    # Who has access through a folder above the item: a user, a team, or everyone. The folder is
    # null when the current user can't open it (see visible_inherited_grants).
    def grant_json(grant)
      grantee =
        case grant.grantee
        when User then { type: "user", id: grant.grantee.id, name: grant.grantee.name }
        when Team then { type: "team", id: grant.grantee.id, name: grant.grantee.name }
        else { type: "everyone" }
        end
      folder = ({ id: grant.folder.id, name: grant.folder.name } if grant.folder)
      { grantee: grantee, access: grant.level.to_s, folder: folder }
    end
end
