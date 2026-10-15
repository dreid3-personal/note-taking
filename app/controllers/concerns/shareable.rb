# The sharing page for notes and folders: GET /notes/:id/sharing shows it, and PATCH saves the
# Everyone setting. Adding, changing and removing shares go to SharesController. Only the item's
# author may open it, and never for a team folder (see "Permissions" in HIGHLEVEL_DESIGN.md).
#
#   class NotesController < ApplicationController
#     include Shareable
#   end
module Shareable
  extend ActiveSupport::Concern

  included do
    # One callback does it all, so it doesn't depend on where the include line sits among the
    # controller's own callbacks.
    before_action :authorize_sharing, only: %i[sharing update_sharing]
  end

  def sharing
    @shares = @shareable.shares.includes(:user, :team).order(:id)
    @teams = Team.order(:name)
    @inherited_grants = visible_inherited_grants(@shareable)
    render "shares/sharing"
  end

  def update_sharing
    if @shareable.update(everyone_access: params.expect(:everyone_access))
      redirect_to sharing_path_for(@shareable), notice: "Everyone: #{helpers.access_label(@shareable.everyone_access)}.",
        status: :see_other
    else
      redirect_to sharing_path_for(@shareable), alert: @shareable.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private
    def authorize_sharing
      return require_current_user unless current_user

      @shareable = controller_name.classify.constantize.find(params[:id])
      require_author!(@shareable)
    end

    def sharing_path_for(item)
      polymorphic_path([ :sharing, item ])
    end
end
