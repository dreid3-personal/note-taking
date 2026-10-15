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

## Getting started

Note Taker is a simple, local-only app for Markdown notes in folders, shared with people, teams
or everyone. One server runs both a web app and a REST API.

### Install

You need Ruby 3.4 (the version in `.ruby-version`; on Windows, use RubyInstaller with DevKit),
Bundler and SQLite. Then, in the project folder:

```bash
bin/setup
```

This installs the gems, creates the database with a sample user, and starts the server.

On Windows PowerShell, put `ruby` in front of every `bin/` command, e.g. `ruby bin/setup`.

### Run

```bash
bin/rails server
```

Open http://localhost:3000. Press Ctrl+C to stop it.

### Use the web app

1. On the **Users** page, add people. Then pick yourself in the **You are** switcher.
2. On the **Teams** page, create teams and add members. Each team gets a team folder that every
   member can edit.
3. On **Notes**, create folders and Markdown notes.
4. Open a note or folder and click **Share** to give people, teams or everyone **Can view** or
   **Can edit**. Access to a folder covers everything inside it.

### Use the REST API

The same server answers JSON under `/api`. Pick who you're acting as with the `X-User-Id` header.
Every response includes ids, so swap in the ones you get back. On Windows, run these from Git
Bash, or use `curl.exe` in PowerShell.

Create two users. No header is needed for this:

```bash
curl -X POST http://localhost:3000/api/users -H "Content-Type: application/json" -d '{"name": "Alice", "email": "alice@example.com"}'
```

```bash
curl -X POST http://localhost:3000/api/users -H "Content-Type: application/json" -d '{"name": "Bob", "email": "bob@example.com"}'
```

As Alice (say id 2), create a note. It's private until she shares it:

```bash
curl -X POST http://localhost:3000/api/notes -H "X-User-Id: 2" -H "Content-Type: application/json" -d '{"title": "Plan", "body": "# Hello"}'
```

As Bob (say id 3), that note is a `404`, exactly as if it didn't exist:

```bash
curl http://localhost:3000/api/notes/1 -H "X-User-Id: 3"
```

As Alice, share it with Bob for viewing:

```bash
curl -X POST http://localhost:3000/api/notes/1/shares -H "X-User-Id: 2" -H "Content-Type: application/json" -d '{"email": "bob@example.com", "access": "view"}'
```

Now Bob can read it, and it shows up under `shared_with_me` on his home:

```bash
curl http://localhost:3000/api/home -H "X-User-Id: 3"
```

As Alice, edit the note. Send the `lock_version` you last read; a stale one gets a `409` instead
of overwriting someone else's change:

```bash
curl -X PATCH http://localhost:3000/api/notes/1 -H "X-User-Id: 2" -H "Content-Type: application/json" -d '{"body": "# Hello again", "lock_version": 0}'
```

[API.md](API.md) lists every endpoint (users, teams and members, home, folders, notes and
shares) and every status code.

### Good to know

- It runs locally only, with no passwords: anyone can switch to any user, and the API trusts
  `X-User-Id`.
- Data lives in a local SQLite file. `bin/rails db:reset` erases it.
- Deletes are permanent, and a folder must be empty before you can delete it.
- If two people edit the same note at once, the second save is refused instead of overwriting.
- Moving notes and folders isn't supported yet.
- Length limits: names 100 characters, emails 254, team and folder names 100, note titles 200,
  note bodies 100,000.
- `bin/ci` runs the linter and tests.
