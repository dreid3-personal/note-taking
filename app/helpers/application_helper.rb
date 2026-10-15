module ApplicationHelper
  # The sidebar section the current page belongs to, so its link can be highlighted.
  def current_section
    case controller_name
    when "users" then :users
    when "teams" then :teams
    else :notes
    end
  end

  def sidebar_link(label, path, section)
    active = section == current_section
    link_to label, path, class: [ "nav-link", { "active" => active } ], aria: { current: ("page" if active) }
  end

  # [name, id] pairs for the "You are" switcher.
  def user_switcher_options
    User.order(:name).pluck(:name, :id)
  end

  def item_icon(item)
    item.is_a?(Folder) ? "📁" : "📄"
  end

  def item_name(item)
    item.is_a?(Folder) ? item.name : item.title
  end

  # A team folder belongs to its team, so it shows "Team" rather than whoever created the team.
  def item_author(item)
    item.is_a?(Folder) && item.team_folder? ? "Team" : item.author.name
  end
end
