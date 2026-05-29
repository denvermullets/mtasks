<!-- last-sha: b3b2f0eef2c97707fc5ec5743692bd1cd92a0952 -->
# What's new

## 2026-05-29
- **Reorder your teams.** A new settings page lets you drag to reorder the teams in your sidebar, separated into teams you own and teams you've joined.
- **Hourglass integration.** Connect projects and issues to Hourglass and keep them in sync both ways — comments, status updates, and messages flow between the two apps in real time, with links to jump straight between them.
- **Clearer team roles.** The sidebar and permissions now do a better job of reflecting who owns, administers, or just belongs to each team.

## 2026-04-27
- **Changelog page.** New in-app changelog so you can see what's shipped recently without leaving the app.
- **Markdown everywhere.** Issues, projects, and comments now render markdown — code blocks, lists, links, and formatting all work.
- **@mention teammates.** Type `@` in an issue or comment to tag a teammate.
- **Themes and fonts.** Pick a color theme (including light mode) and a font style from settings.
- **Better filtering.** Project filters opened up into a menu, plus a "created by" filter, hide-completed-projects-by-default, and a pile of fixes for broken filter queries.
- **Polish round.** Notifications mark themselves read when clicked, cmd+enter submits comments, the header gets a quick "new issue" button, and roadmaps/issues/projects got mobile tweaks.

## 2026-04-22
- **Roadmaps.** New roadmap view lays projects across lanes, with support for multiple projects per lane.
- **CSV export.** Pull your issues out as CSV.
- **Search.** Hit the hotkey to search issues by title and description.
- **GitHub PR automation.** Build rules that move issues automatically based on PR events. Branch-name detection picks up issue shortcodes case-insensitively.
- **API tokens.** Expanded scopes and permissions for API tokens.

## 2026-04-10
- **Issue references.** Type an issue shortcode in any comment or description to autocomplete and link to it. Referenced issues render as inline cards.
- **Comment count on issues.** See at a glance how many comments an issue has.
- **Delete your comments.** Remove a comment you posted (and its notifications go with it).
- **Faster everywhere.** Heavier queries moved to background jobs and many views now render more optimistically.
- **Invite status.** Admins can see whether team invites are pending or accepted.

## 2026-04-03
- **Projects.** New project pages with status, priority, labels, sorting, hotkeys, and a basic velocity chart.
- **File attachments.** Attach files to issues and projects.
- **Blocking issues.** Mark issues as blocking or blocked-by others; the relationships stay in sync as status changes.
- **MCP integration.** Blocking, projects, labels, and comments are now exposed over MCP so AI assistants can work with your tasks.
- **Mobile pass.** A bunch of style tweaks across issues and projects on small screens.

## 2026-02-28
- **Notifications drawer.** A drawer surfaces what changed across your team, backed by full activity history.
- **Avatar colors.** Pick a color for your avatar.
- **Archive teams.** Archive teams you're no longer using.
- **Done means done.** "Completed" issues now consistently track the Done column, with a migration to backfill existing data.

## 2026-01-31
- **Team members.** Invite teammates into your team.
- **Auto-growing inputs.** Comment and description inputs now scale with your text.
- **No more full-page refreshes.** Issue interactions stay snappy via Turbo.

## 2026-01-11
- **Threaded comments.** Replies nest under the comment they're replying to.
- **Better comment input.** Scroll through long threads, and cmd+enter submits.
- **Mobile polish.** Landing page and issue view cleaned up on phones.
- **Board sorting fix.** Empty columns no longer break the board's column order.

## 2026-01-03
- **Cmd+K shortcuts modal.** Hit cmd+k to see the keyboard shortcut cheat sheet.
- **Collapsible columns.** Collapse rows in both board and list views.
- **Quick status changes.** Press `S` on an issue to change its status.
- **My Issues view.** A view that actually shows just the issues assigned to you.
- **"+" buttons everywhere.** Create a new issue directly from any board column or list view.

## 2025-12-28
- **Milestones.** Group issues into milestones, with hotkey support.
- **GitHub app integration.** Connect your GitHub workspace — comments sync, and a single installation can serve multiple teams.
- **Create new teams.** Spin up additional teams from settings.
- **Press L to label.** Quickly add labels from list view with the `L` hotkey.

## 2025-12-21
- **Display options.** Swap between board and row views, with sort and toggle settings that remember themselves per view.
- **Bulk labels.** Create and select labels in bulk.
- **Team settings.** Manage and reorder lanes from team settings.
- **Sub-grouping in lanes.** Lanes can be sub-grouped.
- **Landing page.** First pass at a marketing landing page.

## 2025-12-14
- **Hello, world.** Initial release: auth, team scoping, board and list views, issue creation with priority/lane/owner/project/labels, comments on issues, and CSV import.
