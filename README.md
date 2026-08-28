# JAIT - Just Another Issue Tracker

A modern, team-based issue tracker built with Ruby on Rails, featuring GitHub integration for seamless pull request tracking and collaboration.

## Overview

JAIT is a lightweight project management and issue tracking application designed for development teams. It provides a kanban-style interface for managing issues, with deep GitHub integration to automatically sync and track pull requests alongside your project tasks.

## Features

- **Team-based workspaces** - Organize work across multiple teams and projects
- **Issue management** - Create, track, and manage issues with custom lanes (status columns)
- **Kanban boards** - Visualize work with customizable lanes and drag-and-drop functionality
- **Labels & Milestones** - Categorize and group issues for better organization
- **GitHub Integration** - Automatically sync pull requests from GitHub repositories
- **Pull Request Tracking** - Link issues to PRs and track their status
- **Real-time updates** - Powered by Hotwire/Turbo for responsive UI updates
- **Comments** - Collaborate on issues with threaded comments
- **User preferences** - Customizable views and grouping options

## Tech Stack

- **Ruby on Rails 8.1** - Backend framework
- **PostgreSQL** - Primary database
- **Hotwire (Turbo & Stimulus)** - Frontend interactivity without complex JavaScript
- **Tailwind CSS** - Utility-first styling
- **Solid Queue** - Background job processing
- **Solid Cache** - Database-backed caching
- **Solid Cable** - WebSocket connections for real-time features
- **Octokit** - GitHub API integration
- **JWT** - GitHub App authentication

## Prerequisites

- Ruby 3.3.5 (or compatible version)
- PostgreSQL 14+
- Node.js (for asset compilation)
- GitHub App (for GitHub integration features)

## Setup

### 1. Clone and Install

```bash
git clone <repository-url>
cd mtasks
bundle install
```

### 2. Database Setup

```bash
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed  # Optional: load sample data
```

#### Solid Cable table

The `cable` connection in `config/database.yml` shares the primary DB and sets
`schema_dump: false` (to keep the primary tables out of `db/cable_schema.rb`).
Side effect: `db:schema:load:cable` is a no-op, so `solid_cable_messages` is
**not** created by the standard setup commands. It also isn't defined as a
regular migration, so `db:migrate` won't create it on deploy.

Run this once per environment as a one-time setup (dev on first checkout,
staging/prod on first deploy of solid_cable):

```bash
bin/rails runner 'ActiveRecord::Base.establish_connection(:cable); load Rails.root.join("db/cable_schema.rb")'
```

Verify with `psql -d <db> -c '\dt solid_cable_messages'`. Without this table,
`broadcast_*_later_to` calls (used by webhook-driven Turbo broadcasts) silently
drop.

### 3. Environment Configuration

Create a `.env` file in the project root:

```bash
# Database
DATABASE_URL=postgresql://localhost/mtasks_development

# GitHub App Configuration
GITHUB_APP_ID=your_app_id
GITHUB_APP_SLUG=your-app-slug
GITHUB_APP_PRIVATE_KEY=your_base64_encoded_private_key
GITHUB_WEBHOOK_SECRET=your_webhook_secret

# Rails
SECRET_KEY_BASE=your_secret_key_base

```

#### Vektis Analytics

Analytics is **per team**, and configured in the database rather than the
environment. Each team is its own VEKTIS tenant: a team admin connects the team
to their own VEKTIS account, and nothing at all is emitted for a team that has
not. There is no app-wide enable flag and no ENV vars to set.

To turn it on for a team, sign in as a **team admin** and visit
**Analytics** in the account menu (`/teams/:team_id/settings/vektis_integration`),
then supply:

- **Customer ID** — how the team appears in your VEKTIS dashboard. Several
  mtasks teams may deliberately share one ID.
- **Publishable key** — the `vk_pub_*` key, rate tier 1,000 req/min. This is the
  **only** key safe to expose to the browser, and the app refuses to render one
  that does not carry the `vk_pub_` prefix.
- **Server key** — full-scope key, rate tier 10,000 req/min, used by the
  server-side ingest client. It is never rendered into a page, and the form
  keeps the stored value when the field is submitted blank.

Both keys are read through `Vektis.for(team)`, which returns a
`Vektis::Config` for a connected team and a `Vektis::NullConfig` otherwise —
nothing else in the app should read a team's credentials directly.

The one setting that is *not* per tenant is the ingest URL, which is one
deployment per environment: `config.x.vektis.endpoint`, set in
`config/environments/*.rb`. It defaults to a **locally running vanalytics** on
port 3333 in development and test. The browser SDK's own built-in default *is*
production, so the Stimulus controller passes this value explicitly.

For local work, run vanalytics on port 3333 and connect a team using the key
values it seeds
(`vanalytics/server/src/database/seeds/01_test_org_api_keys.ts`).

##### Which surface an event came from

Every event carries a `source` property, and it is the only field that separates
the three surfaces. The value is stamped by the emitter and cannot be set by a
call site:

- `browser` — the Stimulus controllers, via `app/javascript/vektis.js`.
- `server` — the web app's controllers, jobs and webhook handlers
  (`VektisTracking`).
- `api` — the v1 REST API (`VektisApiTracking`), which covers **both** direct API
  clients and the MCP server. mtasks-mcp is a pure client of this API — every one
  of its tools goes through the same routes with the same `ApiToken` bearer and
  sends no client identifier — so the two are indistinguishable server-side by
  construction. Telling them apart later means adding one header there and a
  `surface` property here.

A gesture is named the same on every surface: creating an issue through the web
form and through the `create_issue` MCP tool both emit `issue-create`/`create`,
and differ only in `source`. Reads have no web counterpart and emit
`api-read`/`query` with an `entity` and, for collections, a `result_count`.

#### Encoding GitHub Private Key

GitHub App private keys need to be base64 encoded for the environment variable:

```bash
base64 -i private-key.pem | tr -d '\n'
```

### 4. Start the Application

```bash
bin/dev
```

The application will be available at `http://localhost:3000`

## GitHub Integration Setup

To enable GitHub integration features:

1. **Create a GitHub App** at https://github.com/settings/apps/new
   - Set Homepage URL to your application URL
   - Set Webhook URL to `https://your-domain.com/webhooks/github`
   - Enable webhooks and set a secret
   - Set permissions:
     - Repository: Pull requests (Read & Write)
     - Repository: Issues (Read & Write)
     - Repository: Webhooks (Read & Write)
   - Subscribe to events: Pull request, Issue comment
   - Generate a private key and download it

2. **Configure Environment Variables**
   - Add your GitHub App ID, slug, encoded private key, and webhook secret to `.env`

3. **Install the App**
   - Navigate to a team's settings in JAIT
   - Click "Connect to GitHub"
   - Select repositories to grant access

## Development

### Running Tests

```bash
bin/rails test
bin/rails test:system  # For system tests
```

### Code Quality

The project uses:
- **RuboCop** - Ruby style guide enforcement
- **Brakeman** - Security vulnerability scanning
- **Bundler Audit** - Dependency vulnerability checking

```bash
bundle exec rubocop
bundle exec brakeman
bundle exec bundler-audit
```

### Coding Conventions

- Follow the RuboCop configuration in `.rubocop.yml`
- Prefer readability over cleverness for long-term maintainability
- Add tests for new logic
- Ask questions if requirements are unclear

## Project Structure

```
app/
├── models/          # ActiveRecord models
├── controllers/     # Request handlers
├── views/           # HTML templates (ERB)
├── services/        # Business logic services
├── jobs/            # Background job processors
└── javascript/      # Stimulus controllers

db/
├── migrate/         # Database migrations
└── seeds.rb         # Sample data

config/
├── routes.rb        # URL routing
└── environments/    # Environment-specific configs
```

## Key Models

- **User** - Authentication and user management
- **Team** - Top-level organization unit
- **Project** - Contains issues and settings
- **Issue** - Core work item
- **Lane** - Status columns (e.g., To Do, In Progress, Done)
- **Label** - Categorization tags
- **Milestone** - Grouping for releases/sprints
- **GithubIntegration** - GitHub App installation per team
- **PullRequest** - Synced GitHub PR data

## Deployment

The application is designed to be deployed on standard Rails hosting platforms. Key considerations:

1. **Database** - Ensure PostgreSQL is configured
2. **Environment Variables** - Set all required ENV vars
3. **Asset Compilation** - Run `bin/rails assets:precompile`
4. **Background Jobs** - Solid Queue runs in-process or as separate worker
5. **WebSockets** - Solid Cable requires no additional infrastructure

### Common Deployment Issues

**Zeitwerk Autoloading**
- Service modules must match their directory structure
- `app/services/gh_integration/` expects `module GhIntegration`
- Avoid naming conflicts between models and service modules

## Contributing

1. Create a feature branch
2. Make your changes
3. Add tests for new functionality
4. Run the test suite and code quality tools
5. Submit a pull request

## License

[Add your license here]

## Support

[Add contact/support information here]
