# Note Taker

## Design Retrospective

### Design choices I spent the most time on

_To fill in: 2–3 design choices, and why you made them._

### If I had more time

_To fill in: what you'd change, add, or stop doing._

---

A simple, local-only app for Markdown notes in folders, shared with people, teams or everyone.

## Install

You need Ruby 3.4 (the version in `.ruby-version`; on Windows, use RubyInstaller with DevKit),
Bundler and SQLite. Then, in the project folder:

```bash
bin/setup
```

This installs the gems, creates the database with a sample user, and starts the server.

On Windows PowerShell, put `ruby` in front of every `bin/` command, e.g. `ruby bin/setup`.

## Run

```bash
bin/rails server
```

Open http://localhost:3000. Press Ctrl+C to stop it.

The same server has a REST API under `/api`. Pick the user with the `X-User-Id` header:

```bash
curl -H "X-User-Id: 1" http://localhost:3000/api/home
```

[API.md](API.md) lists the endpoints.

## Use

Add people on the Users page, then pick yourself in the "You are" switcher. Create teams; each
gets a team folder. Create folders and Markdown notes, then share them as Can view or Can edit
with people, teams or everyone. Access to a folder covers everything inside it.

## Good to know

- It runs locally only, with no passwords: anyone can switch to any user, and the API trusts
  `X-User-Id`.
- Data lives in a local SQLite file. `bin/rails db:reset` erases it.
- Deletes are permanent, and a folder must be empty before you can delete it.
- If two people edit the same note at once, the second save is refused instead of overwriting.
- Moving notes and folders isn't supported yet.
- Length limits: names 100 characters, emails 254, team and folder names 100, note titles 200,
  note bodies 100,000.
- `bin/ci` runs the linter and tests.
