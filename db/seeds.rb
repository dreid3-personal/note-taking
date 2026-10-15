# Creates the records a fresh database needs. It is idempotent, so it can run any number of times,
# including through `bin/rails db:seed:replant`.

# One sample user, so the "You are" switcher has someone to pick.
User.find_or_create_by!(email: "sample@example.com") do |user|
  user.name = "Sample User"
end
