# The current user's top level, as on the Notes page: see NotesHome.
class Api::HomeController < Api::BaseController
  def show
    home = NotesHome.new(current_user)
    render json: NotesHome::SECTIONS.keys.to_h { |section| [ section, home.public_send(section).map { |item| item_json(item) } ] }
  end
end
