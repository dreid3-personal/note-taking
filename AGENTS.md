# AGENTS.md

Guidance for AI agents working in this repository.

## Project

Note Taker is a simple, local-only note-taking app, built with Rails 8.1 and Ruby 3.4. It works much like
Google Drive: users keep Markdown notes in folders and share them with specific users, teams, or
everyone, for viewing or editing.

## Design docs: read for context

Read these before making changes. They are the source of truth for how the app should behave.

- **[HIGHLEVEL_DESIGN.md](HIGHLEVEL_DESIGN.md):** the data model, sharing and permission rules,
  denied-access behavior, and the code structure (which class owns which rule).
- **[UI_DESIGN.md](UI_DESIGN.md):** every page and route, the layout, and the approach: server-rendered
  ERB, Turbo, and Bootstrap CSS only.

If a change alters behavior described in these docs, update the docs in the same change.

## Test plan: use to verify changes

**[TEST_PLAN.md](TEST_PLAN.md)** defines how every change is verified.

1. **Run the automated checks.** A change is done only when this passes:

   ```bash
   bin/ci
   ```

   It runs RuboCop and the test suite. Add or update tests for what you changed, following the
   test plan's lists. Every bug fix gets a test that fails without the fix.
2. **Walk through the relevant E2E walkthrough** in a browser, following the plan's setup and
   reporting conventions:
   - anything touching notes, folders, sharing, teams or permissions: **E2E 1: Privacy**, which is
     the most important;
   - user pages or the `User` model: **E2E 2: Users**;
   - team pages or the `Team` model: **E2E 3: Teams**.

Report what you verified, and anything you couldn't.

## Conventions

- **Keep it simple.** Prefer what Rails already provides. Don't add JavaScript frameworks, build
  tools or new gems without a clear need.
- **Keep the code modular, as described in "Code structure" in HIGHLEVEL_DESIGN.md.** Permission
  logic belongs in `AccessResolver` and the `Authorization` concern, never in views or scattered
  through controllers.
- **Check permissions on the server for every request.** Hiding a button is not enough.
- **Style:** RuboCop with `rubocop-rails-omakase`. Run `bin/rubocop -a` to fix most issues
  automatically.
- **New scripts in `bin/`** must be marked executable in git, because the repo is also used on
  macOS and Linux:

  ```bash
  git update-index --chmod=+x bin/<script>
  ```

## Common commands

| Task | Command |
|---|---|
| Set up and start the app | `bin/setup` |
| Start the server | `bin/rails server`, then open http://localhost:3000 |
| Run all checks | `bin/ci` |
| Run unit and request tests | `bin/rails test` |
| Run browser tests | `bin/rails test:system` |
| Lint | `bin/rubocop` |
| Reset the local database (erases data) | `bin/rails db:reset` |
