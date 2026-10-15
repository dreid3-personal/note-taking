# Note Taker

## Design Retrospective

### Design choices I spent the most time on

**1. The data model.** I wanted something simple and flexible that would feel familiar to anyone
who uses a note-taking app today. Most of my time went into how notes should be organized between
users and teams, and how people would expect those to interact, including privacy and visibility.

What I settled on:

- **Notes live in folders, and folders can nest,** like a file system. Anything can also sit at
  the top level.
- **Users and teams are deliberately minimal.** A user has a name and an email. A team has a name
  and members, and a user can be on many teams.
- **Every team gets its own team folder automatically,** and every current member can edit it.
  Joining a team gives you its folder, and leaving takes it away.
- **Every note and folder has an author,** the person who created it. The author always keeps
  access to their own items.
- **Notes are stored as plain Markdown,** then rendered and sanitized when shown. That keeps the
  door open to richer editing later without migrating any data.

**2. Privacy and visibility.** Again, I wanted behavior people would expect, and something that
works for a wide range of uses: from private notes nobody else should see, to meeting notes shared
with a team, to a page the whole company can read.

What I settled on:

- **Private by default.** A new note or folder is visible only to its author.
- **Share with anyone, at the level you choose.** The author can share any note or folder with
  specific people, specific teams, or everyone, as **Can view** or **Can edit**. These mix
  freely, for example: everyone can view, one team can edit.
- **Folders share their contents.** Sharing a folder covers everything inside it, at any depth.
  Inherited access only ever adds: a note can be shared more widely than its folder, never less.
- **The author stays in control.** Only the author can change sharing or delete an item, so an
  editor can't lock the author out or remove their work.
- **Checked on the server, every time.** One class (`AccessResolver`) owns all the access rules,
  and every request goes through it. With no access, the app answers `404 Not Found`, exactly as
  if the item didn't exist, so nobody can find private notes by guessing URLs.

### If I had more time

1. **Help people find their notes:** favorites, filters and search, so the notes someone cares
   about come up first.
2. **Moving notes and folders** between folders. It's designed, but it was cut for time, so for
   now items stay where they're created.
3. **Real authentication:** passwords for users and auth tokens for the REST API, in place of the
   user switcher and the `X-User-Id` header. That would make it a full app with a complete
   backend service.
4. **Merging simultaneous edits:** today, saving a stale copy is refused with "This note was
   changed by someone else." Instead, I'd merge changes that don't overlap automatically, and only
   ask the user when two edits really collide.

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
