# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_10_130312) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "comments", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.bigint "issue_id", null: false
    t.bigint "parent_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["issue_id"], name: "index_comments_on_issue_id"
    t.index ["parent_id"], name: "index_comments_on_parent_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "github_installations", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "github_account_login"
    t.string "github_account_type"
    t.string "installation_id", null: false
    t.datetime "last_webhook_at"
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["installation_id"], name: "index_github_installations_on_installation_id", unique: true
    t.index ["workspace_id"], name: "index_github_installations_on_workspace_id"
  end

  create_table "github_repository_subscriptions", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "github_installation_id", null: false
    t.string "github_repo_full_name", null: false
    t.datetime "last_webhook_at"
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["github_installation_id", "github_repo_full_name", "active"], name: "index_gh_repo_subs_for_webhook_lookup"
    t.index ["github_installation_id"], name: "idx_on_github_installation_id_f25fecf4b0"
    t.index ["team_id", "github_installation_id", "github_repo_full_name"], name: "index_gh_repo_subs_on_team_installation_repo", unique: true
    t.index ["team_id"], name: "index_github_repository_subscriptions_on_team_id"
  end

  create_table "issue_dependencies", force: :cascade do |t|
    t.bigint "blocked_issue_id", null: false
    t.bigint "blocking_issue_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_issue_id"], name: "index_issue_dependencies_on_blocked_issue_id"
    t.index ["blocking_issue_id", "blocked_issue_id"], name: "idx_on_blocking_issue_id_blocked_issue_id_e966cd8a46", unique: true
    t.index ["blocking_issue_id"], name: "index_issue_dependencies_on_blocking_issue_id"
  end

  create_table "issue_labels", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "issue_id", null: false
    t.bigint "label_id", null: false
    t.datetime "updated_at", null: false
    t.index ["issue_id"], name: "index_issue_labels_on_issue_id"
    t.index ["label_id"], name: "index_issue_labels_on_label_id"
  end

  create_table "issue_pull_requests", force: :cascade do |t|
    t.boolean "comment_posted", default: false, null: false
    t.datetime "comment_posted_at"
    t.datetime "created_at", null: false
    t.bigint "issue_id", null: false
    t.bigint "pull_request_id", null: false
    t.datetime "updated_at", null: false
    t.index ["issue_id", "pull_request_id"], name: "index_issue_pull_requests_on_issue_and_pr", unique: true
    t.index ["issue_id"], name: "index_issue_pull_requests_on_issue_id"
    t.index ["pull_request_id"], name: "index_issue_pull_requests_on_pull_request_id"
  end

  create_table "issue_references", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "referenced_issue_id", null: false
    t.bigint "source_issue_id", null: false
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["referenced_issue_id"], name: "index_issue_references_on_referenced_issue_id"
    t.index ["source_issue_id", "referenced_issue_id", "source_type"], name: "idx_issue_refs_unique", unique: true
    t.index ["source_issue_id"], name: "index_issue_references_on_source_issue_id"
    t.index ["user_id"], name: "index_issue_references_on_user_id"
  end

  create_table "issues", force: :cascade do |t|
    t.datetime "archived_at"
    t.bigint "assignee_id"
    t.datetime "canceled_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.text "description"
    t.date "due_date"
    t.integer "estimate"
    t.bigint "lane_id", null: false
    t.bigint "milestone_id"
    t.bigint "parent_issue_id"
    t.integer "priority", default: 4
    t.bigint "project_id"
    t.datetime "started_at"
    t.bigint "team_id", null: false
    t.integer "team_number"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_issues_on_assignee_id"
    t.index ["creator_id"], name: "index_issues_on_creator_id"
    t.index ["lane_id"], name: "index_issues_on_lane_id"
    t.index ["milestone_id"], name: "index_issues_on_milestone_id"
    t.index ["parent_issue_id"], name: "index_issues_on_parent_issue_id"
    t.index ["project_id"], name: "index_issues_on_project_id"
    t.index ["team_id", "team_number"], name: "index_issues_on_team_id_and_team_number", unique: true
    t.index ["team_id"], name: "index_issues_on_team_id"
  end

  create_table "labels", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.string "name"
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_labels_on_team_id"
  end

  create_table "lanes", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "position"
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_lanes_on_team_id"
  end

  create_table "milestones", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.date "due_date"
    t.string "name"
    t.date "start_date"
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_milestones_on_team_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id", null: false
    t.bigint "comment_id"
    t.datetime "created_at", null: false
    t.bigint "issue_id", null: false
    t.text "message", null: false
    t.datetime "read_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "version_id"
    t.index ["actor_id"], name: "index_notifications_on_actor_id"
    t.index ["comment_id"], name: "index_notifications_on_comment_id"
    t.index ["issue_id"], name: "index_notifications_on_issue_id"
    t.index ["user_id", "created_at"], name: "index_notifications_on_user_id_and_created_at"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "pending_github_setups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "installation_id"
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["expires_at"], name: "index_pending_github_setups_on_expires_at"
    t.index ["installation_id"], name: "index_pending_github_setups_on_installation_id"
    t.index ["workspace_id"], name: "index_pending_github_setups_on_workspace_id"
  end

  create_table "project_labels", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "label_id", null: false
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["label_id"], name: "index_project_labels_on_label_id"
    t.index ["project_id"], name: "index_project_labels_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.integer "completed_issues_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.date "due_date"
    t.bigint "lead_id"
    t.bigint "milestone_id"
    t.string "name"
    t.integer "priority", default: 4
    t.date "start_date"
    t.string "status", default: "backlog"
    t.bigint "team_id", null: false
    t.integer "total_issues_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "velocity_score", default: 0, null: false
    t.index ["lead_id"], name: "index_projects_on_lead_id"
    t.index ["milestone_id"], name: "index_projects_on_milestone_id"
    t.index ["team_id"], name: "index_projects_on_team_id"
  end

  create_table "pull_requests", force: :cascade do |t|
    t.string "author_login"
    t.string "base_ref"
    t.text "body"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.datetime "github_created_at"
    t.bigint "github_repository_subscription_id", null: false
    t.datetime "github_updated_at"
    t.string "head_ref"
    t.string "html_url"
    t.boolean "merged", default: false, null: false
    t.datetime "merged_at"
    t.integer "pr_number", null: false
    t.string "state"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["github_repository_subscription_id"], name: "index_pull_requests_on_github_repository_subscription_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.string "refresh_token"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["refresh_token"], name: "index_sessions_on_refresh_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "team_invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.bigint "invited_by_id", null: false
    t.integer "status", default: 0, null: false
    t.bigint "team_id", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["invited_by_id"], name: "index_team_invitations_on_invited_by_id"
    t.index ["team_id", "email", "status"], name: "index_team_invitations_on_team_email_pending", unique: true, where: "(status = 0)"
    t.index ["team_id"], name: "index_team_invitations_on_team_id"
    t.index ["token"], name: "index_team_invitations_on_token", unique: true
  end

  create_table "team_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["team_id"], name: "index_team_memberships_on_team_id"
    t.index ["user_id"], name: "index_team_memberships_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "identifier"
    t.integer "issue_counter", default: 0
    t.string "name"
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["identifier"], name: "index_teams_on_identifier", unique: true
    t.index ["workspace_id"], name: "index_teams_on_workspace_id"
  end

  create_table "user_preferences", force: :cascade do |t|
    t.string "completed_filter"
    t.datetime "created_at", null: false
    t.string "group_by", default: "status"
    t.string "order_by", default: "manual"
    t.boolean "show_empty_groups", default: true
    t.boolean "show_empty_rows", default: false
    t.boolean "show_sub_issues", default: true
    t.string "sub_group_by", default: "none"
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "view_mode", default: "board"
    t.json "visible_properties", default: ["id", "priority", "assignee", "labels"]
    t.index ["team_id"], name: "index_user_preferences_on_team_id"
    t.index ["user_id", "team_id"], name: "index_user_preferences_on_user_id_and_team_id", unique: true
    t.index ["user_id"], name: "index_user_preferences_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_color", default: "bg-blue-600", null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.string "password_digest"
    t.integer "role", default: 0
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.jsonb "object"
    t.jsonb "object_changes"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  create_table "workspaces", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.bigint "owner_id", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_workspaces_on_owner_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "comments", "comments", column: "parent_id"
  add_foreign_key "comments", "issues"
  add_foreign_key "comments", "users"
  add_foreign_key "github_installations", "workspaces"
  add_foreign_key "github_repository_subscriptions", "github_installations"
  add_foreign_key "github_repository_subscriptions", "teams"
  add_foreign_key "issue_dependencies", "issues", column: "blocked_issue_id"
  add_foreign_key "issue_dependencies", "issues", column: "blocking_issue_id"
  add_foreign_key "issue_labels", "issues"
  add_foreign_key "issue_labels", "labels"
  add_foreign_key "issue_pull_requests", "issues"
  add_foreign_key "issue_pull_requests", "pull_requests"
  add_foreign_key "issue_references", "issues", column: "referenced_issue_id"
  add_foreign_key "issue_references", "issues", column: "source_issue_id"
  add_foreign_key "issue_references", "users"
  add_foreign_key "issues", "issues", column: "parent_issue_id"
  add_foreign_key "issues", "lanes"
  add_foreign_key "issues", "milestones"
  add_foreign_key "issues", "projects"
  add_foreign_key "issues", "teams"
  add_foreign_key "issues", "users", column: "assignee_id"
  add_foreign_key "issues", "users", column: "creator_id"
  add_foreign_key "labels", "teams"
  add_foreign_key "lanes", "teams"
  add_foreign_key "milestones", "teams"
  add_foreign_key "notifications", "comments"
  add_foreign_key "notifications", "issues"
  add_foreign_key "notifications", "users"
  add_foreign_key "notifications", "users", column: "actor_id"
  add_foreign_key "pending_github_setups", "workspaces"
  add_foreign_key "project_labels", "labels"
  add_foreign_key "project_labels", "projects"
  add_foreign_key "projects", "milestones"
  add_foreign_key "projects", "teams"
  add_foreign_key "projects", "users", column: "lead_id"
  add_foreign_key "pull_requests", "github_repository_subscriptions"
  add_foreign_key "sessions", "users"
  add_foreign_key "team_invitations", "teams"
  add_foreign_key "team_invitations", "users", column: "invited_by_id"
  add_foreign_key "team_memberships", "teams"
  add_foreign_key "team_memberships", "users"
  add_foreign_key "teams", "workspaces"
  add_foreign_key "user_preferences", "teams"
  add_foreign_key "user_preferences", "users"
  add_foreign_key "workspaces", "users", column: "owner_id"
end
