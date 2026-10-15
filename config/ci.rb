# Run using bin/ci

CI.run do
  step "Setup", "ruby bin/setup --skip-server"

  step "Style: Ruby", "ruby bin/rubocop"

  step "Security: Importmap vulnerability audit", "ruby bin/importmap audit"
  step "Tests: Rails", "ruby bin/rails test"
  step "Tests: Seeds", "ruby bin/rails db:seed:replant RAILS_ENV=test"

  # Optional: Run system tests
  # step "Tests: System", "ruby bin/rails test:system"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
