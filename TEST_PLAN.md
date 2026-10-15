# Note Taker — Test Plan

How we verify Note Taker as we build it. The rules being tested are defined in
[HIGHLEVEL_DESIGN.md](HIGHLEVEL_DESIGN.md), and the screens in [UI_DESIGN.md](UI_DESIGN.md).

There are three areas, in priority order:

1. **Privacy:** private and team items are only visible to the people they're meant for. This
   covers most of the app: being a user, being on a team, and reading, creating and editing notes.
2. **Users:** users can be created, and emails must be unique.
3. **Teams:** teams can be created, and team names must be unique.

Each area is checked in two ways:

- **Automated checks:** linting, plus tests that use Rails' built-in tools (Minitest, plus Capybara
  for browser tests). They catch regressions on every change.
- **An end-to-end (E2E) walkthrough** that an agent performs by hand in a browser, to confirm the
  real app behaves correctly from a user's point of view.

## Automated checks

Everything below runs with one command:

```bash
bin/ci
```

On Windows (PowerShell), put `ruby` in front of every `bin/` command in this plan: `ruby bin/ci`,
`ruby bin/rubocop`, `ruby bin/rails server`, and so on. A bare `bin/ci` in PowerShell opens the file
through its file association instead of running it, and can leave a stale `$LASTEXITCODE` of 0, which
looks like a pass.

A change is done only when `bin/ci` passes. Every rule in the design docs should have at least one
test, and every bug fix should add a test that fails without the fix.

### Linting

RuboCop checks Ruby code style, using Rails' standard `rubocop-rails-omakase` rules. It runs as the
first step of `bin/ci`, or on its own:

```bash
bin/rubocop
```

Use `bin/rubocop -a` to fix most issues automatically.

### Unit tests (`test/models/`)

Most of the testing happens here. Each unit from "Code structure" in
[HIGHLEVEL_DESIGN.md](HIGHLEVEL_DESIGN.md) is tested on its own, with fixtures. Unit tests are fast,
so they cover every case, including the edge cases; the slower tests below only check how the units
are wired together.

**`AccessLevel`**
- Ordering is `none` < `view` < `edit`, and picking the highest of several levels works, including
  from an empty list (`none`).
- `edit` allows viewing and editing, `view` allows only viewing, and `none` allows neither.

**`AccessResolver`** (the most important unit)
- Each way access can come about, on its own: author; team folder member; `everyone_access`; direct
  user share; team share.
- Each of those inherited from a parent folder, and from a grandparent folder.
- Combinations, where the highest level wins. For example, view from a folder plus edit from the
  note's own share gives edit.
- Inherited access can't be reduced: a note set to `everyone_access: none` inside a folder shared
  for viewing is still viewable.
- No access at all gives `none`, including for a user on an unrelated team.
- Team membership changes: joining a team grants its shares and its team folder; leaving removes them.
- Share changes take effect immediately: lowering a share from edit to view gives view, and
  removing it gives `none` (unless another rule still grants access).
- An author keeps access to their own note inside a team folder after leaving the team.

**`NotesHome`**
- Every accessible item appears exactly once, in the right section (My notes, Team folders or
  Shared with me).
- An item inside an accessible folder isn't listed at the top level.
- An inaccessible item never appears.
- Ordering: folders first, then notes, each alphabetical.

**`Breadcrumbs`**
- A folder's trail ends with the folder; a note's ends with its folder; a top-level note has none.
- The section is where the trail's top item is listed: My notes, Team folders or Shared with me.
- Folders the user can't open are left out, including the team folder of a team the author left.

**`MarkdownRenderer`**
- Headings, lists, task lists, tables and code blocks render.
- `<script>` tags, `on…=` event attributes and `javascript:` links are removed.

**Models**
- **Length limits,** for each field in HIGHLEVEL_DESIGN.md's "Length limits" (`User` name and
  email, `Team` name, `Folder` name, `Note` title and body): a value at the limit saves, and one
  character over is rejected with "is too long". A note body's `
` is saved as `
`.
- `User`: name and email required; emails saved lowercased and trimmed; duplicate emails rejected,
  including ones differing only by case or spaces; the unique index rejects a duplicate even when
  the validation is skipped.
- `Team`: name required; duplicate names rejected on create and rename, ignoring case and spaces;
  the unique index catches duplicates; renaming also renames the team folder.
- `Team.create_with_folder`: creates the team, its team folder and the creator's membership. If any
  part fails, none of them is saved.
- `Membership`: a user can't be added to the same team twice.
- `Folder`: its `parent_id` can't point at itself or its subfolders; can't be deleted while it has contents;
  team folders can't be deleted, moved or re-shared.
- `Note`: title required; saving with an old `lock_version` fails and keeps the newer content.
- `Share`: exactly one of note or folder; exactly one of user or team; no duplicates for the same
  item and grantee. Each rule is enforced by both a validation and a database constraint.

### Request tests (`test/controllers/`)

These check that every route enforces permissions on the server, not just by hiding buttons. The
`Authorization` concern is tested here.

For every note, folder and sharing route (`show`, `edit`, `update`, `destroy`, sharing
pages, and the `shares` endpoints):

- **No access:** `404`, and nothing changes.
- **View access, attempting a change:** a redirect with "You don't have permission to do that.",
  and nothing changes.
- **Edit access but not the author, attempting to share or delete:** redirected, and nothing changes.
- **Team folders:** renaming, sharing or deleting is refused for everyone.
- **No current user picked:** redirected to the Notes page's "Pick a user" message.

- **Moving isn't supported:** `/notes/:id/move` and `/folders/:id/move` are `404`, and the edit
  forms ignore `folder_id` and `parent_id`, even from the author.

Also check that the Users and Teams forms show validation errors with a `422` status, and that one
form per controller (users, teams, folders, notes) gives a `422` with the "is too long" error for
an over-long value and has a `maxlength` on each limited field.

### API tests (`test/controllers/api/`, `test/integration/api_privacy_test.rb`)

The REST API ([API.md](API.md)) gets the same checks, as JSON. For every `/api` endpoint:

- **No `X-User-Id`, or an unknown one:** `401`, and nothing changes (except listing and adding users).
- **No access:** `404`, with the same body as a missing record, and nothing changes.
- **Too little access** (a viewer editing; an editor changing `everyone_access`, sharing or
  deleting; anyone renaming, sharing or deleting a team folder): `403`, and nothing changes.
- **Success:** the right status (`200`, `201` with `Location`, `204`) and body.
- **Bad input:** a `422` with the errors for validation failures; a `400` for malformed JSON and for
  arrays or objects in place of a single value; a `409` for a stale or missing note `lock_version`.

`api_privacy_test.rb` scripts the core of E2E 1 over `/api` only, from an empty database: private
notes, team folders (including leaving and rejoining), sharing with a user and lowering edit to
view, a team share inherited through a folder, `everyone_access`, and the `409` on a concurrent edit.

### System test (`test/system/`)

One short browser test of the main flow keeps the pages wired together. Create a user, create a
note, share it with a second user, and switch to that user to see it. The E2E walkthroughs below
cover everything else in more detail.

## E2E walkthroughs (for an agent)

### Setup

Before each walkthrough:

1. Reset the development database. **This erases all local data.**

   ```bash
   bin/rails db:reset
   ```

2. Start the server:

   ```bash
   bin/rails server
   ```

3. Open http://localhost:3000 in a browser.

### Conventions

- **"As Alice"** means: pick Alice in the sidebar's "You are" switcher first.
- **Write down the URL of every note and folder you create,** for example `/notes/3`. Many steps
  visit these URLs directly as another user, to prove that hidden items are really blocked and not
  just missing from the list.
- **"Hidden"** means all of these are true:
  - the item isn't listed anywhere on the Notes pages;
  - its URL, and its `/edit` and `/sharing` URLs, all show a 404 page.
- **"View only"** means:
  - the item opens and its content is visible;
  - there are no Edit, Share or Delete buttons;
  - visiting its `/edit` URL redirects back with "You don't have permission to do that.", and the
    content is unchanged.
- **Reporting:** for every step, record pass or fail and what you saw. On a failure, take a
  screenshot, then carry on with the next step where possible. End with a summary listing every
  failure.

---

### E2E 1: Privacy and the core note flow (most important)

#### People

| User | Email | Teams |
|---|---|---|
| Alice | alice@example.com | Engineering |
| Bob | bob@example.com | Engineering |
| Carol | carol@example.com | Design |
| Dave | dave@example.com | none |

#### 1.0 Set up people and teams

1. On the Users page, add Alice, Bob, Carol and Dave.
   **Expect:** all four are listed and appear in the switcher.
2. As Alice, create the team **Engineering**, then add Bob to it.
   **Expect:** the team page lists Alice and Bob.
3. As Carol, create the team **Design**.
   **Expect:** the team page lists only Carol.

#### 1.1 Private notes stay private

1. As Alice, on the Notes page, create a top-level note called **Alice private**, with this body:

   ```markdown
   # Heading
   - [ ] a task
   <script>alert("xss")</script>
   ```

   **Expect:**
   - It is listed under My notes.
   - Its page shows a heading and a checkbox list item.
   - No alert pops up, and the script text isn't run.
2. As Alice, create a top-level folder called **Alice folder**. Inside it, create a note called
   **Alice nested**.
   **Expect:** the folder is listed under My notes. The note appears only inside the folder, with
   breadcrumbs `Notes › My notes › Alice folder`.
3. As Bob, open the Notes page.
   **Expect:** My notes is empty. Team folders shows only Engineering. Shared with me is empty.
4. As Bob, check **Alice private**, **Alice folder** and **Alice nested**.
   **Expect:** all three are hidden.
5. As Dave, repeat steps 3 and 4.
   **Expect:** the same results, except Team folders is empty.

#### 1.2 Team folders

1. As Alice, open the Engineering team folder and create a note called **Eng plan**.
   **Expect:**
   - It appears inside Engineering.
   - The folder has no Rename, Share or Delete buttons.
2. As Bob, open Engineering, then **Eng plan**.
   **Expect:**
   - Bob can read it.
   - An Edit button is shown, but no Share or Delete.
3. As Bob, edit **Eng plan**, change the body, and save.
   **Expect:** the change is saved, and Alice sees it too.
4. As Bob, visit **Eng plan**'s `/sharing` URL directly.
   **Expect:** a redirect with "You don't have permission to do that."
5. As Bob, inside Engineering, create a note called **Bob eng note**.
   **Expect:** it is listed with Bob as its author. Alice can open and edit it.
6. As Carol, check Engineering, **Eng plan** and **Bob eng note**.
   **Expect:** all three are hidden. Carol's Team folders shows only Design.
7. As Alice, check the Design team folder.
   **Expect:** it is hidden.
8. As Alice, remove Bob from Engineering on its team page.
9. As Bob, check the Notes page and the URLs from this section.
   **Expect:**
   - Engineering and **Eng plan** are hidden.
   - **Bob eng note** is still visible to Bob, because he is its author, and is listed under My notes.
10. As Alice, add Bob back to Engineering.
    **Expect:** Bob sees Engineering and **Eng plan** again. **Bob eng note** is back inside
    Engineering and no longer under My notes.

#### 1.3 Sharing with specific people

1. As Alice, open the sharing page for **Alice private**. Add `nobody@example.com` with Can view.
   **Expect:** "No user with that email." and nothing is added.
2. Add `  CAROL@Example.com ` (uppercase, with spaces) with Can view.
   **Expect:** Carol is added and listed by name with Can view.
3. As Carol, open the Notes page.
   **Expect:** **Alice private** is listed under Shared with me, and it is view only.
4. As Dave, check **Alice private**.
   **Expect:** it is hidden.
5. As Alice, change Carol's access to Can edit.
6. As Carol, edit **Alice private** and save.
   **Expect:**
   - The save works, and Alice sees the change.
   - Carol still has no Share or Delete buttons.
7. As Carol, open **Alice private**'s edit page in tab 1 and leave it open. In tab 2, switch to Alice
   and change Carol's access back to Can view.
   **Expect:** Carol is listed with Can view.
8. In tab 2, switch back to Carol. In tab 1, change the body and save.
   **Expect:**
   - A redirect with "You don't have permission to do that.", and the change isn't saved.
   - **Alice private** is now view only for Carol, but still listed under her Shared with me.
9. As Alice, remove Carol's share.
   **Expect:** **Alice private** is hidden from Carol again.

#### 1.4 Sharing with teams, and inherited access

1. As Alice, share **Alice folder** with the team Design, with Can view.
2. As Carol, open the Notes page.
   **Expect:**
   - **Alice folder** is listed under Shared with me.
   - **Alice nested** isn't listed separately, but appears inside the folder.
   - The folder has no New note or New folder buttons, and **Alice nested** is view only.
3. As Alice, share **Alice nested** itself with Design, with Can edit.
   **Expect:** the sharing page for **Alice nested** shows, under "Also has access through a parent
   folder", Design with view access from **Alice folder**.
4. As Carol:
   **Expect:**
   - Carol can now edit **Alice nested**.
   - **Alice folder** is still view only, so there are still no New buttons inside it.
5. As Dave, check **Alice folder** and **Alice nested**.
   **Expect:** both are hidden.
6. As Carol, add Dave to Design.
   **Expect:** Dave now sees **Alice folder** under Shared with me, and can edit **Alice nested**.
7. As Carol, remove Dave from Design.
   **Expect:** both items are hidden from Dave again.

#### 1.5 Sharing with everyone

1. As Alice, set Everyone to Can view on **Alice private**.
2. As Dave:
   **Expect:** **Alice private** is listed under Shared with me, and it is view only.
3. As Alice, set Everyone to Can edit.
4. As Dave, edit **Alice private** and save.
   **Expect:** the save works, and Dave still has no Share or Delete buttons.
5. As Alice, set Everyone back to No access.
   **Expect:** **Alice private** is hidden from Dave.

#### 1.6 Two people editing at once

1. As Alice, open **Eng plan**'s edit page in two browser tabs.
2. In tab 1, change the body and save.
   **Expect:** "Note saved."
3. In tab 2, make a different change and save.
   **Expect:**
   - "This note was changed by someone else." is shown, and tab 2's change isn't saved.
   - Reloading the note shows tab 1's change.

#### 1.7 Deleting

Moving isn't supported yet, so this section only deletes.

1. As Alice, try to delete **Alice folder** while it contains **Alice nested**.
   **Expect:** "Move or delete everything inside this folder first." Nothing is deleted.
2. As Alice, delete **Alice private** and **Alice nested**, then **Alice folder**.
   **Expect:**
   - Both are gone from every user's Notes page.
   - Their URLs show a 404 for everyone, including Alice.
3. As Alice, visit the Engineering team folder's `/edit` and `/sharing` URLs directly.
   **Expect:** both redirect with "You don't have permission to do that."

---

### E2E 2: Users

1. Open the Users page.
   **Expect:** the seeded sample user is listed.
2. Add the user **Erin**, `erin@example.com`.
   **Expect:** Erin is listed and appears in the switcher.
3. Add the user **Erin Two**, `erin@example.com`.
   **Expect:**
   - An error says the email is already taken, and no user is added.
   - The form keeps what was typed.
4. Add a user with the email `  ERIN@Example.COM  `.
   **Expect:** the same error, because the check ignores case and spaces.
5. Submit the form with the name blank, then again with the email blank.
   **Expect:** each time, an error says the field can't be blank, and no user is added.
6. Add the user **Frank**, `frank@example.com`, then switch to Frank.
   **Expect:** Frank is added. After switching, the Notes page shows Frank's empty My notes.

---

### E2E 3: Teams

1. As Erin (create Erin first as in E2E 2), add the team **Marketing**.
   **Expect:**
   - Marketing is listed with 1 member.
   - Its team page lists Erin.
   - Erin's Notes page shows Marketing under Team folders.
2. Add a team called **Marketing** again, then `  marketing  `.
   **Expect:** each time, an error says the name is already taken, and no team is added.
3. Submit the form with the name blank.
   **Expect:** an error says the name can't be blank.
4. Add the team **Sales**. On Marketing's page, open the Add a member dropdown.
   **Expect:** Erin isn't offered, because she's already a member.
5. Add Frank to Marketing.
   **Expect:**
   - Frank is listed, and the member count on the Teams page is 2.
   - As Frank, Marketing appears under Team folders.
6. Remove Frank from Marketing.
   **Expect:** as Frank, Marketing is hidden.
7. Rename Marketing to **Sales**.
   **Expect:** an error says the name is already taken, and the name doesn't change.
8. Rename Marketing to **Growth**.
   **Expect:** the team and its team folder are both called Growth now.
