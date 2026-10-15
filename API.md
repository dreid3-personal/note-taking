# Note Taker — REST API

A JSON API next to the HTML pages. `bin/rails server` serves both, at http://localhost:3000. It
follows the same rules as the pages: see "Permissions" and "Denied access" in
[HIGHLEVEL_DESIGN.md](HIGHLEVEL_DESIGN.md).

## Basics

- **JSON in, JSON out.** Send bodies with `Content-Type: application/json`, as top-level keys
  (`{"title": "Plan"}`, not `{"note": {...}}`). Unknown keys are ignored.
- **Current user: the `X-User-Id` header**, the id of an existing user. **This is not real
  authentication:** like the "You are" switcher, anyone can act as any user. The app is for local
  use only. Only `GET /api/users` and `POST /api/users` work without it, so the first user can be
  created.
- **PATCH changes only the keys sent.**

### Status codes

| Code | When | Body |
|---|---|---|
| `200` | Success | The resource |
| `201` | Created, with a `Location` header | The new resource |
| `204` | Deleted | Empty |
| `400` | Malformed JSON, a missing required key, or a value that should be a single value but is an array or object | `{"error": "Bad request"}` |
| `401` | No `X-User-Id`, or not the id of an existing user | `{"error": "Send the X-User-Id header ..."}` |
| `403` | Some access to the item, but not enough (a viewer editing, an editor sharing or deleting, anything changing a team folder's name, sharing or existence) | `{"error": "You don't have permission to do that."}` |
| `404` | No access at all, exactly like a record that doesn't exist. Ids that aren't a whole number count as not existing | `{"error": "Not found"}` |
| `409` | Updating a note with a stale or missing `lock_version` | `{"error": "This note was changed by someone else."}` |
| `422` | Validation failed, including deleting a folder that isn't empty | `{"errors": {"title": ["can't be blank"]}}` |

### Items

Lists (home sections, folder `children`, the index pages) hold short items, sorted folders first,
then notes, each alphabetical:

```json
{"type": "folder", "id": 3, "name": "Alice folder", "parent_id": null, "team_id": null, "author": {"id": 1, "name": "Alice"}}
{"type": "note", "id": 2, "title": "Alice nested", "folder_id": 3, "author": {"id": 1, "name": "Alice"}, "updated_at": "..."}
```

`parent_id` and `folder_id` are `null` when the item is at the top level, and also when the user
can't open that folder, so a note shared on its own doesn't reveal the folder it sits in.

## Endpoints

The examples use Alice (user 1).

### Users

`GET /api/users` lists users, by name. No current user needed.

```bash
curl http://localhost:3000/api/users
```

`POST /api/users` adds a user (`name`, `email`; the email is stripped and lowercased, and must be
unique). No current user needed.

```bash
curl -X POST http://localhost:3000/api/users -H "Content-Type: application/json" -d '{"name": "Alice", "email": "alice@example.com"}'
```

`GET /api/users/:id` shows one user: `{"id", "name", "email"}`.

```bash
curl http://localhost:3000/api/users/2 -H "X-User-Id: 1"
```

### Teams

Any user can see and manage any team.

`GET /api/teams` lists teams, by name: `[{"id", "name"}]`.

```bash
curl http://localhost:3000/api/teams -H "X-User-Id: 1"
```

`POST /api/teams` creates a team (`name`), its team folder, and makes the current user a member.

```bash
curl -X POST http://localhost:3000/api/teams -H "X-User-Id: 1" -H "Content-Type: application/json" -d '{"name": "Engineering"}'
```

`GET /api/teams/:id` shows a team with its `members`.

```bash
curl http://localhost:3000/api/teams/1 -H "X-User-Id: 1"
```

`PATCH /api/teams/:id` renames the team (`name`), and its team folder with it.

```bash
curl -X PATCH http://localhost:3000/api/teams/1 -H "X-User-Id: 1" -H "Content-Type: application/json" -d '{"name": "Platform"}'
```

`POST /api/teams/:team_id/members` adds a member (`user_id`). An unknown user, or one who is
already a member, is a `422`.

```bash
curl -X POST http://localhost:3000/api/teams/1/members -H "X-User-Id: 1" -H "Content-Type: application/json" -d '{"user_id": 2}'
```

`DELETE /api/teams/:team_id/members/:user_id` removes a member: `204`, or `404` if they aren't one.

```bash
curl -X DELETE http://localhost:3000/api/teams/1/members/2 -H "X-User-Id: 1"
```

### Home

`GET /api/home` is the current user's top level, as on the Notes page:
`{"my_notes": [...], "team_folders": [...], "shared_with_me": [...]}`. Items inside a folder the
user can open are listed in that folder instead.

```bash
curl http://localhost:3000/api/home -H "X-User-Id: 1"
```

### Folders

`GET /api/folders` lists every folder the current user can open.

```bash
curl http://localhost:3000/api/folders -H "X-User-Id: 1"
```

`POST /api/folders` creates a folder (`name`, optional `parent_id`). The parent needs edit access;
the current user becomes the author.

```bash
curl -X POST http://localhost:3000/api/folders -H "X-User-Id: 1" -H "Content-Type: application/json" -d '{"name": "Alice folder"}'
```

`GET /api/folders/:id` shows a folder, the current user's `access` (`view` or `edit`), and its
`children`.

```bash
curl http://localhost:3000/api/folders/3 -H "X-User-Id: 1"
```

`PATCH /api/folders/:id` changes `name` (edit access, never a team folder) and `everyone_access`
(`none`, `view` or `edit`; the author only, never a team folder).

```bash
curl -X PATCH http://localhost:3000/api/folders/3 -H "X-User-Id: 1" -H "Content-Type: application/json" -d '{"name": "Plans", "everyone_access": "view"}'
```

`DELETE /api/folders/:id` deletes an empty folder (the author only, never a team folder). A folder
with anything inside is a `422`.

```bash
curl -X DELETE http://localhost:3000/api/folders/3 -H "X-User-Id: 1"
```

### Notes

`GET /api/notes` lists every note the current user can open.

```bash
curl http://localhost:3000/api/notes -H "X-User-Id: 1"
```

`POST /api/notes` creates a note (`title`, `body` in Markdown, optional `folder_id`). The folder
needs edit access; the current user becomes the author.

```bash
curl -X POST http://localhost:3000/api/notes -H "X-User-Id: 1" -H "Content-Type: application/json" -d '{"title": "Plan", "body": "# Hello", "folder_id": 3}'
```

`GET /api/notes/:id` shows a note: the short item plus `body`, `body_html` (rendered and
sanitized), `lock_version`, and the current user's `access`.

```bash
curl http://localhost:3000/api/notes/1 -H "X-User-Id: 1"
```

`PATCH /api/notes/:id` changes `title` and `body` (edit access) and `everyone_access` (the author
only). It needs the `lock_version` you last read: if the note changed since, or none is sent, it is
a `409` and nothing changes. Read the note again and retry.

```bash
curl -X PATCH http://localhost:3000/api/notes/1 -H "X-User-Id: 1" -H "Content-Type: application/json" -d '{"body": "# Hello again", "lock_version": 0}'
```

`DELETE /api/notes/:id` deletes a note (the author only).

```bash
curl -X DELETE http://localhost:3000/api/notes/1 -H "X-User-Id: 1"
```

### Shares

All of these are for the item's author only, and never for a team folder.

`GET /api/notes/:note_id/shares` and `GET /api/folders/:folder_id/shares` show the item's sharing
settings: `everyone_access`, its `shares`, and `inherited`, the access it gets from the folders
above it (`{"grantee": {"type": "user" | "team" | "everyone", "id", "name"}, "access", "folder": {"id", "name"}}`).
`folder` is `null` when the current user can't open that folder.

```bash
curl http://localhost:3000/api/notes/1/shares -H "X-User-Id: 1"
```

`POST /api/notes/:note_id/shares` and `POST /api/folders/:folder_id/shares` share the item with a
user by `email` (case and spaces don't matter) or a team by `team_id`, with `access` `view` or
`edit`. Each share is `{"id", "access", "note_id", "folder_id", "user", "team"}`.

```bash
curl -X POST http://localhost:3000/api/folders/3/shares -H "X-User-Id: 1" -H "Content-Type: application/json" -d '{"email": "carol@example.com", "access": "view"}'
```

`PATCH /api/shares/:id` changes a share's `access`.

```bash
curl -X PATCH http://localhost:3000/api/shares/1 -H "X-User-Id: 1" -H "Content-Type: application/json" -d '{"access": "edit"}'
```

`DELETE /api/shares/:id` removes a share.

```bash
curl -X DELETE http://localhost:3000/api/shares/1 -H "X-User-Id: 1"
```
