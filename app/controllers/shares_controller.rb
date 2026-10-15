# Adds, changes and removes a note's or folder's shares, from its sharing page. Like the page,
# only the item's author may do this, and never for a team folder. The item always comes from the
# database: the share's own note or folder, or the posted note_id or folder_id, checked like any
# other id.
class SharesController < ApplicationController
  before_action :require_current_user
  before_action :set_item, only: :create
  before_action :set_share, only: %i[update destroy]
  before_action -> { require_author!(@item) }

  # Shares the item with a user, looked up by email, or a team.
  def create
    grantee = find_grantee
    key = grantee.is_a?(Team) ? :team : :user

    if grantee.nil?
      redirect_back_to_sharing alert: share_params[:email].present? ? "No user with that email." : "Pick a team."
    elsif grantee == @item.author
      redirect_back_to_sharing alert: "You're the author, so you already have access."
    elsif @item.shares.exists?(key => grantee)
      redirect_back_to_sharing alert: already_shared(grantee)
    else
      share = @item.shares.new(key => grantee, access: share_params[:access])
      if share.save
        redirect_back_to_sharing notice: "#{grantee.name} added: #{helpers.access_label(share.access)}."
      else
        redirect_back_to_sharing alert: share.errors.full_messages.to_sentence
      end
    end
  rescue ActiveRecord::RecordNotUnique
    # Two quick submits can both pass the check; the unique index stops the second.
    redirect_back_to_sharing alert: already_shared(grantee)
  end

  def update
    if @share.update(access: share_params[:access])
      redirect_back_to_sharing notice: "#{@share.grantee.name}: #{helpers.access_label(@share.access)}."
    else
      redirect_back_to_sharing alert: @share.errors.full_messages.to_sentence
    end
  end

  def destroy
    @share.destroy!
    redirect_back_to_sharing notice: "#{@share.grantee.name} removed."
  end

  private
    # The posted share[note_id] or share[folder_id]: exactly one, and a single id. Anything else,
    # such as an array, is treated as an id that doesn't exist.
    def set_item
      posted = params[:share]
      raise ActiveRecord::RecordNotFound unless posted.is_a?(ActionController::Parameters)

      ids = { Note => posted[:note_id], Folder => posted[:folder_id] }.compact_blank
      raise ActiveRecord::RecordNotFound unless ids.size == 1 && ids.values.first.is_a?(String)

      model, id = ids.first
      @item = model.find(id)
    end

    def set_share
      @share = Share.find(params[:id])
      @item = @share.item
    end

    # The user with the posted email (normalized like User's, so case and spaces don't matter), or
    # the posted team.
    def find_grantee
      if share_params[:email].present?
        User.find_by(email: share_params[:email])
      elsif share_params[:team_id].present?
        Team.find_by(id: share_params[:team_id])
      end
    end

    def already_shared(grantee)
      "#{grantee.name} already has access. Change it in the list above."
    end

    # Non-scalar values, such as arrays, are dropped.
    def share_params
      params.expect(share: %i[email team_id access])
    end

    def redirect_back_to_sharing(flash)
      redirect_to polymorphic_path([ :sharing, @item ]), **flash, status: :see_other
    end
end
