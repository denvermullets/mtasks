# Issue tracker: jait (MCP)

Issues for this repo live in jait, team **Issue Tracker** (prefix `JAIT`, `team_id: 4`). Use the `mcp__jait__*` MCP tools for everything. Never use `gh issue`.

## Model

- **Issue** = a ticket. It's referred to by identifier (`JAIT-123`), but the tools take its numeric `issue_id`. Resolve one with `get_issue_by_identifier`.
- **Project** = an epic: a named body of work with a long markdown description (Why / Goal / Decisions / Build order / Out of scope) and many issues.
- **Lanes** (status): Backlog `13`, In Progress `14`, Done `15`, Cancelled `16`. New issues default to Backlog. Re-check with `list_lanes` if an ID fails.
- **Me** (the driving dev): Ryan Vaznis, `user_id: 3`.

## Conventions

- **Create an issue**: `create_issue` with `team_id: 4`, `title`, `description` (markdown), plus `project_id` / `label_ids` / `priority` as needed.
- **Read an issue**: `get_issue_by_identifier` (or `get_issue`), plus `list_comments` for the thread.
- **List issues**: `list_issues` with `team_id: 4`, filtered by `project_id`, `lane_id`, `assignee_id` or `priority`.
- **Sub-issue**: `create_issue` with `parent_issue_id`.
- **Comment**: `create_comment`.
- **Apply / remove labels**: `update_issue` with `label_ids`. This **replaces** the whole set, so read the current labels first and send the merged list. Look up label IDs with `list_labels` and create missing ones with `create_label`.
- **Close**: comment first, then `update_issue` with `lane_id: 15` (Done), or `16` (Cancelled) for wontfix or out-of-scope.
- **Blocking**: `create_issue_dependency` (`direction: blocked_by` / `blocking`). Inspect with `list_issue_dependencies`.
- **Editing long descriptions**: prefer the section-scoped description tools where they exist over rewriting a whole issue or project description.

## When a skill says "publish to the issue tracker"

Create a jait issue on team 4. If the work spans several issues, create a project for it first and file the issues into it.

## When a skill says "fetch the relevant ticket"

Read it as described in **Read an issue** above.

## Wayfinding operations

Used by `/wayfinder`. **Every map gets its own jait project.** Charting creates the project and its first tickets. Every follow-up ticket becomes another issue in that same project. To continue, run `/wayfinder` on the project again: each run takes one issue off the frontier.

- **Map**: a new project (`create_project`, team 4) named after the effort, labelled `wayfinder:map` (pass `label_ids` and create the label with `create_label` the first time). The project **description** holds the map body (Destination / Notes / Decisions so far / Not yet specified / Out of scope). Load it with `get_project` and update it with `update_project` or the section tools. A user may hand over the map as a project name or ID; resolve it with `list_projects` / `get_project`.
- **Child ticket**: an issue in that project (`project_id`) carrying one `wayfinder:<type>` label (`research` / `prototype` / `grilling` / `task`). Create the label with `create_label` the first time it's needed.
- **Blocking**: native jait dependencies via `create_issue_dependency`. A ticket is unblocked when every blocker is in Done or Cancelled.
- **Frontier query**: `list_issues` with `project_id`. Keep issues that are not in Done or Cancelled, are unassigned, and have no open blockers. The first in map order wins.
- **Claim**: `update_issue` with `assignee_id: 3`, as the session's first write.
- **Resolve**: `create_comment` with the answer, then `update_issue` with `lane_id: 15`, then append a context pointer (name + identifier) to the project description's Decisions-so-far.
