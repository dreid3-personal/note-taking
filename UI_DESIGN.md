# Note Taker — UI Design

The screens and interactions for Note Taker. For the data model and permission rules, see
[HIGHLEVEL_DESIGN.md](HIGHLEVEL_DESIGN.md).

## Approach

- **A plain, server-rendered Rails app.** Standard RESTful controllers and ERB views, built with
  Rails' own helpers (`form_with`, `link_to`, `button_to`). No React and no JavaScript build step.
- **Rails defaults only.** Turbo, which `rails new` already set up, makes links and form submissions
  feel fast with no extra code. There is no custom JavaScript, except one `onchange` on the user
  switcher.
- **Bootstrap 5, CSS only.** The `bootstrap.min.css` file is saved into
  `vendor/assets/stylesheets/` and loaded from the layout. It works offline and needs no gem, npm or
  CDN. We don't use Bootstrap's JavaScript, so there are no modals or dropdown menus. Every action is
  a normal page or a form.
- **Icons are emoji** (📁 folder, 📄 note) rather than an icon library.

## Layout

Every page shares one layout: a fixed sidebar on the left and the page content on the right.

```
┌──────────────┬──────────────────────────────────────────────┐
│ Note Taker   │                                              │
│              │                                              │
│ 📄 Notes     │                Page content                  │
│ 👤 Users     │                                              │
│ 👥 Teams     │                                              │
│              │                                              │
│              │                                              │
│ You are:     │                                              │
│ [Alice   ▾]  │                                              │
└──────────────┴──────────────────────────────────────────────┘
```

- The sidebar has three links: **Notes**, **Users** and **Teams**. The current section is highlighted.
- **"You are" switcher:** a `<select>` of all users at the bottom of the sidebar. Changing it submits
  a small form (`PATCH /current_user`) that stores the user's id in the session and reloads the page.
- **Flash messages** such as "Note saved." or "This note was changed by someone else." appear as
  Bootstrap alerts at the top of the content area.
- **No current user:** until a user is chosen, the Notes page shows "Pick a user in the sidebar to
  get started." If there are no users at all, it links to the Users page. The database seeds create
  one sample user.

## Notes (the home page)

`/` goes to the Notes page. It works like Google Drive: a list of folders and notes for one location,
with breadcrumbs for navigating back up.

### Top level

```
Notes                                         [+ New folder] [+ New note]

My notes
  📁 Recipes                       Alice        Oct 14
  📄 Todo                          Alice        Oct 15

Team folders
  📁 Engineering                   Team         Oct 10

Shared with me
  📁 Design ideas                  Bob          Oct 12
  📄 Welcome                       Carol        Oct 01
```

The top level has three sections:

The top level lists every item the current user can access whose parent folder they can't open
(or that has no parent). Everything else is reached by opening folders, so each item appears in
exactly one place. Those items are grouped into:

- **My notes:** the current user's own items. Usually these are their top-level folders and notes. It
  also catches their notes inside a folder they've lost access to, such as the team folder of a team
  they left.
- **Team folders:** the folder of each team the current user belongs to.
- **Shared with me:** items other people own that the current user can access, through a direct
  share, a team share or `everyone_access`. A note inside a folder that is shared with the user
  appears inside that folder, not here.

Each row shows an icon, the name (a link), the author, and when it was last updated. Folders are
listed before notes, and each group is in alphabetical order.

### Inside a folder (`/folders/:id`)

```
Notes › Team folders › Engineering › Specs

Specs                   [Rename] [Share] [Move] [Delete]  [+ New folder] [+ New note]

  📁 Archive                       Alice        Oct 11
  📄 API spec                      Bob          Oct 15
```

- Breadcrumbs show where you are, and each part is a link (see "Breadcrumbs" below).
- The list works like the top level, without the sections.
- Buttons appear only if the current user is allowed to use them (see the permissions table in
  [HIGHLEVEL_DESIGN.md](HIGHLEVEL_DESIGN.md)): **Rename** with edit access; **Share**, **Move** and
  **Delete** for the author only; **New folder** and **New note** with edit access. Team folders
  have no Rename, Share, Move or Delete.

### Breadcrumbs

Folder and note pages start with a trail back to the Notes page. It follows the way the item is
reached from the top level, so it never shows a folder the current user can't open:

```
Notes › My notes › Alice folder › Specs               (a folder of mine)
Notes › Team folders › Engineering                    (a note in the Engineering team folder)
Notes › Shared with me › Design ideas › Drafts        (a folder inside a folder shared with me)
Notes › Shared with me                                (a note shared with me on its own)
```

1. **Notes**, the top level.
2. The section of the top level that lists the item, or the highest folder above it that the user
   can open: **My notes**, **Team folders** or **Shared with me**. It links to that section of the
   Notes page.
3. The folders from there down. A folder's trail ends with the folder itself; a note's ends with
   the folder it is in, and the note's title is the page heading.

Folders above that the user can't open are left out. For example, a note Bob wrote in the
Engineering team folder, after Bob leaves the team, shows `Notes › My notes`.

## Note pages

| Page | Route | Contents |
|---|---|---|
| View | `GET /notes/:id` | Breadcrumbs, title, rendered Markdown body, author and last-updated time. Buttons: **Edit**, **Share**, **Move**, **Delete**, each shown only when allowed. |
| New | `GET /notes/new?folder_id=…` | Title field and a large Markdown textarea. The folder comes from where you clicked **New note**. |
| Edit | `GET /notes/:id/edit` | Same form as New. A hidden `lock_version` field supports the "changed by someone else" check. |
| Move | `GET /notes/:id/move` | A `<select>` of every folder where the user has `edit` access, shown as indented paths, plus "Top level". It submits to `PATCH /notes/:id/move`. |

Delete is a `button_to` with Turbo's built-in confirmation ("Delete this note?").

## Folder pages

| Page | Route | Contents |
|---|---|---|
| New | `GET /folders/new?parent_id=…` | Name field. Without `parent_id`, the folder goes at the top level. |
| Rename | `GET /folders/:id/edit` | Name field. |
| Move | `GET /folders/:id/move` | Same as moving a note, except it leaves out the folder itself and its subfolders. It submits to `PATCH /folders/:id/move`. |

Delete is a `button_to` with a confirmation. When the folder isn't empty, the page explains: "Move or
delete everything inside this folder first."

## Sharing page

Notes and folders share the same page: `GET /notes/:id/sharing` or `GET /folders/:id/sharing`.
Only the author can open it.

```
Share "API spec"

Everyone                      [No access ▾]           [Save]

People and teams with access
  Bob (bob@example.com)       [Can edit ▾]            [Remove]
  👥 Engineering               [Can view ▾]            [Remove]

Add a person
  [email address        ]     [Can view ▾]            [Add]

Add a team
  [Pick a team ▾]             [Can view ▾]            [Add]

Also has access through a parent folder:
  👥 Design (can view, from 📁 Specs)
```

- Each row and form is its own small form that posts to `shares` (`POST /shares`,
  `PATCH /shares/:id`, `DELETE /shares/:id`). The Everyone form submits to `PATCH /notes/:id/sharing`
  or `PATCH /folders/:id/sharing`. This avoids writing any JavaScript.
- Adding a person looks up the email. If no user has that email, it shows "No user with that email."
- The access dropdowns offer **Can view** and **Can edit**. The "Everyone" dropdown also offers
  **No access**.
- The **"Also has access through a parent folder"** list is read-only. It explains access that this
  page can't remove, because inherited access can only be added to, never taken away. Each person
  or team is listed once, at the highest level they inherit, from the nearest folder that gives it.
  The list runs nearest folder first; within a folder, its author (or team), then Everyone, then
  its shares in the order they were added.

## Users page (`/users`)

```
Users

  Name            Email
  Alice           alice@example.com
  Bob             bob@example.com

Add a user
  Name [            ]  Email [                    ]  [Add user]
```

A table of users and a form to add one, both on the same page. If the form is invalid, for example
because the email is already taken, the page shows the error next to the field and keeps what was
typed. Editing and deleting users are out of scope for now.

The Users page works without a current user, so the first user can be added before anyone is picked
in the switcher.

## Teams pages

### Teams list (`/teams`)

```
Teams

  Name            Members
  Engineering     3
  Design          2

Add a team
  Name [            ]  [Add team]
```

Each team name links to that team's page. Creating a team also creates its team folder and adds the
creator as its first member. A duplicate or blank name shows an error next to the field, like the
Users form. Renaming a team follows the same rule.

### Team page (`/teams/:id`)

```
Engineering                                    [Rename]  [Open team folder]

Members
  Alice           alice@example.com            [Remove]
  Bob             bob@example.com              [Remove]

Add a member
  [Pick a user ▾]                               [Add]
```

- The **Add a member** dropdown lists users who aren't in the team yet.
- **Rename** opens `GET /teams/:id/edit`, a name field. It changes the team name and its team
  folder's name together.
- **Open team folder** goes to the team folder. It is shown only to members, since only they can
  open it.
- Any user can manage any team: for a local app, that's simpler than having team admins. The Teams
  pages do need a current user, who becomes the creator of any team they add.
