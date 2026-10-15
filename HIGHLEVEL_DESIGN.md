# Note Taker — High-Level Design

A simple, local-only note-taking app built with Rails 8.1. It works much like Google Drive: notes
live in folders, and notes and folders can each be shared with specific users, specific teams, or
everyone.

## Goals

- Users organize notes into folders.
- For each note or folder, the author chooses who can view and who can edit it: just them, specific
  users, specific teams, or everyone.
- Each team has a folder that all its members can use.
- Keep everything simple: minimal user and team models, Markdown notes.

## Non-goals (for now)

- Real-time collaborative editing (multiple people editing one note at once).
- Images or other attachments in notes.
- Trash or undo for deleted items.
- Deployment; the app runs locally only.
- Passwords or real authentication.
- Moving notes and folders. An item stays in the folder it was created in.

## Data model

```
users           id, name, email (unique)
teams           id, name (unique)
memberships     id, user_id, team_id            unique index on (user_id, team_id)
folders         id, name, author_id, parent_id (nullable), team_id (nullable, unique), everyone_access
notes           id, title, body, author_id, folder_id (nullable), everyone_access, lock_version
shares          id, folder_id (nullable), note_id (nullable),
                user_id (nullable), team_id (nullable), access
```

All tables also have the standard `created_at` / `updated_at` timestamps.

### Length limits

| Field | Max characters |
|---|---|
| `users.name` | 100 |
| `users.email` | 254 |
| `teams.name` | 100 (a team folder takes its team's name, so it matches `folders.name`) |
| `folders.name` | 100 |
| `notes.title` | 200 |
| `notes.body` | 100,000 |

Each limit is a model validation with a friendly error, such as "is too long (maximum is 200
characters)"; the body's error also says how long the body is. The form field has a matching
`maxlength`. There is no database constraint. A note body's `
` line breaks, which browsers
submit, are saved as `
`, so the textarea's `maxlength` and the validation count the same way.

"Item" below means a note or a folder.

### Users and teams

- A user can belong to many teams, and a team has many users, joined through `memberships`.
- Teams only have a name.
- A user's name and email are both required, and a team's name is required.
- **Emails and team names are unique, ignoring case.** Leading and trailing spaces are stripped and
  emails are lowercased before saving, using Rails' `normalizes`. Uniqueness is enforced twice: by a
  model validation, which gives a friendly error message, and by a unique database index, which
  catches anything the validation misses.

### Folders

- A folder sits inside another folder (`parent_id`) or at the top level (`parent_id` is `NULL`).
- A note sits inside a folder (`folder_id`) or at the top level (`folder_id` is `NULL`).
- Moving isn't supported yet: an item stays where it was created, and the edit forms ignore
  `folder_id` and `parent_id`. The `Folder` model still refuses a `parent_id` that would put a
  folder inside itself or one of its own subfolders.
- A folder can only be deleted when it's empty. With no trash, this prevents deleting a whole tree,
  including other people's notes, by accident.

### Team folders

Creating a team also creates its **team folder**, a top-level folder with the team's name and
`team_id` set. It is special:

- Every current member of the team has `edit` access to it and everything inside it. This comes from
  the membership itself, not from a share.
- It is renamed along with the team and can't be deleted, moved, or have its sharing changed.
  Its `author_id` is the user who created the team. That is only a record: unlike other items,
  being the author of a team folder gives no access, so a creator who leaves the team loses it like
  any other member.

### Ownership

Every item has an **author** (`author_id`, required, references `users`): the person who created it.
The author can always view and edit their items (team folders are the one exception, see above).

### Access levels

Access is either `view` or `edit`, and `edit` includes `view`. Every column that holds an access level
is a string-backed Rails enum, with a database check constraint that limits it to its allowed values.

An item's access is set in two places:

- **`everyone_access`** on the item: `none` (default), `view` or `edit`. Applies to every user.
- **`shares`**: one row grants `view` or `edit` on one item to one user or one team. Database check
  constraints make each row set exactly one of `folder_id` and `note_id`, and exactly one of
  `user_id` and `team_id`. Unique indexes stop the same user or team being shared the same item
  twice. When sharing with a user, the author finds them by email; the row stores the `user_id`.

A team share applies to whoever is in the team at the time. Adding someone to a team gives them
access to the team's shared items, and removing them takes it away.

### Inherited access

As in Google Drive, access to a folder also covers everything inside it, at any depth. Sharing a
folder with a team for viewing lets the team view every note and subfolder in it.

Inherited access can only add access, never remove it. An item's sharing settings can give more
access than its parent folder, but not less.

### Effective access

A user's access to an item is the **highest** of the following, checked for the item itself and for
every folder above it:

1. `edit`, if they are the author (except of a team folder);
2. `edit`, if it is the team folder of a team they belong to;
3. the `everyone_access` setting;
4. the share for them directly, if any;
5. the shares for any team they belong to.

If the result is `none`, the item is hidden from them. The four cases from the requirements are
just combinations of these settings:

| Who can access | How |
|---|---|
| Only the creator | `everyone_access: none` and no shares (the default for a new item) |
| Specific users | One `shares` row per user |
| Specific teams | One `shares` row per team |
| Everyone | `everyone_access: view` or `edit` |

These can be mixed. For example, a note can be viewable by everyone, editable by one team, and also
editable by one specific user outside that team.

Folders are rarely nested more than a few levels deep, so the ancestor check can simply walk up
`parent_id` in Ruby. If that ever gets slow, SQLite supports recursive queries
(`WITH RECURSIVE`).

### Permissions

| Action | Who |
|---|---|
| View an item, or a folder's contents | Anyone with `view` access |
| Edit a note's title and body; rename a folder | Anyone with `edit` access |
| Create a note or folder inside a folder | Anyone with `edit` access to that folder |
| Move an item | Not supported yet (see "Non-goals") |
| Change sharing (`everyone_access`, shares) | Only the author |
| Delete an item | Only the author (folders only when empty) |

Keeping sharing and deletion with the author means an editor can't lock the author out or remove
the item.

### Denied access

Permissions are checked on the server for every request, not just by hiding buttons:

- **No access at all:** the server responds `404 Not Found`, exactly as if the item didn't exist.
  That way someone can't tell whether a private note exists by guessing its URL.
- **Some access, but not enough** (for example, a viewer opening the edit page or submitting an
  edit): the server redirects to the item with "You don't have permission to do that." and nothing
  changes. The new item's author is whoever creates it, even inside someone else's folder.
- **No current user picked:** pages that need one redirect to the Notes page, which asks the
  visitor to pick a user.
- **Folders above a shared item:** the sharing page lists who has access through parent folders,
  but never names a folder the current user can't open (`Authorization#visible_inherited_grants`).

The JSON REST API under `/api` ([API.md](API.md)) checks the same rules through the same
`Authorization` concern; `Api::BaseController` only changes how a refusal looks. It always answers
in JSON:

- **No current user** (a missing or unknown `X-User-Id` header): `401`. Only listing and adding
  users work without one.
- **No access at all:** `404 {"error": "Not found"}`, identical to a record that doesn't exist.
- **Some access, but not enough:** `403 {"error": "You don't have permission to do that."}`, and
  nothing changes.
- **Malformed params** (bad JSON, a missing required key, or an array or object where a single
  value belongs): `400`. They're checked before any lookup that could reveal whether a hidden
  record exists, and an id that isn't a whole number counts as one that doesn't exist (`404`).
- **Validation failures:** `422 {"errors": {"field": ["..."]}}`.
- **A stale or missing `lock_version`** when updating a note: `409`.

### Concurrent edits

Simultaneous editing isn't supported, but we guard against silent overwrites with Rails' built-in
optimistic locking (`lock_version`). If a note changed after a user opened it, their save fails with
a "this note was changed by someone else" message instead of overwriting the other person's edits.

## Notes and Markdown

- `title`: required string.
- `body`: text, written in Markdown and stored as plain text.
- Editing uses a plain textarea; there is no rich editor.
- When a note is displayed, its body is rendered to HTML with a Markdown gem (e.g. `commonmarker`),
  with GitHub-flavored extensions such as tables and task lists.
- The rendered HTML must be sanitized, because note bodies are user input.

Storing plain Markdown keeps the door open for later upgrades, such as a Write/Preview tab or
GitHub-style image paste via Active Storage, with no data migration.

## Login

No passwords for now. The sidebar has a "You are: [user]" switcher, and the chosen user's id is
stored in the session as the current user.

Password login can be added later with Rails 8's built-in `bin/rails generate authentication`.
That adds a `password_digest` column and a sessions table, and doesn't change the rest of this design.

## Code structure

The rules above live in small, single-purpose classes rather than in controllers or views, so
each can be unit tested on its own. Following Rails convention, plain Ruby classes go in
`app/models/` next to the Active Record models.

| Unit | Responsibility | Depends on |
|---|---|---|
| `User`, `Team`, `Membership`, `Folder`, `Note`, `Share` | Associations, validations, normalization, and simple scopes. No permission logic. | Database |
| `AccessLevel` | A value object for `none` < `view` < `edit`. Compares levels, picks the highest, and answers "does this level allow viewing / editing?" | Nothing |
| `AccessResolver` | Works out a user's effective access to one item, following the rules in "Effective access" above: `access_to(item)` returns an `AccessLevel`, with `can_view?` / `can_edit?` shortcuts. `AccessResolver.inherited_grants(item)` lists who gets access from the folders above the item (grantee, level, source folder), for the sharing page's "Also has access through a parent folder". | The item, its parent folders, its shares, and the user's team ids |
| `NotesHome` | Builds the Notes page's top level: the items in My notes, Team folders and Shared with me. Also sorts item lists (folders first, each alphabetical) for folder pages. | `AccessResolver` |
| `Breadcrumbs` | The trail above a note or folder page: the Notes page section the item is reached from, then the folders from there down that the user can open (see "Breadcrumbs" in UI_DESIGN.md). | `AccessResolver`, `NotesHome` |
| `MarkdownRenderer` | Turns a Markdown string into sanitized HTML. | The Markdown gem |
| `Team.create_with_folder` | Creates a team, its team folder, and the creator's membership in one transaction. | `Team`, `Folder`, `Membership` |
| `Authorization` (controller concern) | `require_access!(item, :view)` or `(item, :edit)`, `(item, :rename)` for renaming a folder (edit access, never a team folder), and `require_author!(item)` for sharing, moving and deleting (never a team folder). Responds with a 404 or a redirect, as described in "Denied access"; a missing record gets the same 404. Views ask `allowed_to?(action, item)` to decide which buttons to show. | `AccessResolver` |
| `Shareable` (controller concern) and `SharesController` | The sharing page for notes and folders (`sharing`, `update_sharing` for the Everyone setting), and adding, changing and removing shares. Every request checks `require_author!` on the item, loaded from the database (the share's own item, or the posted id). | `Authorization`, `AccessResolver.inherited_grants` |

Controllers only load records, call `Authorization`, save, and render. Views only display what
they're given.
