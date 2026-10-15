module SharesHelper
  ACCESS_LABELS = { "none" => "No access", "view" => "Can view", "edit" => "Can edit" }.freeze

  # "Can view" for "view", and so on.
  def access_label(level)
    ACCESS_LABELS.fetch(level.to_s)
  end

  # [label, value] pairs for an access dropdown. Only the Everyone setting offers No access.
  def access_options(everyone: false)
    ACCESS_LABELS.except(*("none" unless everyone)).invert.to_a
  end

  # "Bob (bob@example.com)" or "👥 Engineering".
  def grantee_label(grantee)
    case grantee
    when Team then "👥 #{grantee.name}"
    when User then "#{grantee.name} (#{grantee.email})"
    when :everyone then "Everyone"
    end
  end

  # "👥 Design (can view, from 📁 Specs)", for the "Also has access through a parent folder" list.
  # A folder the current user can't open isn't named: "from a parent folder".
  def inherited_grant_label(grant)
    grantee = grant.grantee.is_a?(User) ? grant.grantee.name : grantee_label(grant.grantee)
    source = grant.folder ? "📁 #{grant.folder.name}" : "a parent folder"
    "#{grantee} (#{access_label(grant.level).downcase}, from #{source})"
  end
end
