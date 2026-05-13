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

ActiveRecord::Schema[8.1].define(version: 2026_05_13_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_user_id"
    t.bigint "auditable_id", null: false
    t.string "auditable_type", null: false
    t.jsonb "changed_data", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_user_id"], name: "index_audit_logs_on_actor_user_id"
    t.index ["auditable_type", "auditable_id", "created_at"], name: "index_audit_logs_on_auditable_and_created_at"
  end

  create_table "blocks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "leader_id"
    t.string "name"
    t.datetime "updated_at", null: false
    t.bigint "village_id", null: false
    t.index ["village_id"], name: "index_blocks_on_village_id"
  end

  create_table "cable_token_nonces", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "nonce", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_cable_token_nonces_on_expires_at"
    t.index ["nonce"], name: "index_cable_token_nonces_on_nonce", unique: true
    t.index ["user_id"], name: "index_cable_token_nonces_on_user_id"
  end

  create_table "campaign_cycles", force: :cascade do |t|
    t.boolean "carry_forward_data", default: true, null: false
    t.datetime "created_at", null: false
    t.string "cycle_type", default: "primary", null: false
    t.date "end_date", null: false
    t.integer "monthly_quota_target", default: 6000
    t.string "name", null: false
    t.jsonb "settings", default: {}, null: false
    t.date "start_date", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["start_date", "end_date"], name: "index_campaign_cycles_on_start_date_and_end_date"
    t.index ["status"], name: "index_campaign_cycles_on_status"
  end

  create_table "campaigns", force: :cascade do |t|
    t.string "candidate_names"
    t.datetime "created_at", null: false
    t.string "election_type"
    t.integer "election_year"
    t.string "facebook_url"
    t.date "general_election_date"
    t.string "instagram_url"
    t.string "logo_url"
    t.string "name"
    t.string "party"
    t.string "primary_color"
    t.date "primary_election_date"
    t.string "secondary_color"
    t.boolean "show_pace", default: false, null: false
    t.text "signup_share_prompt"
    t.date "started_at"
    t.string "status"
    t.text "thank_you_share_prompt"
    t.string "tiktok_url"
    t.string "twitter_url"
    t.datetime "updated_at", null: false
    t.text "welcome_sms_template"
    t.index ["status"], name: "index_campaigns_on_status"
  end

  create_table "districts", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.integer "coordinator_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.integer "number"
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_districts_on_campaign_id"
  end

  create_table "dpg_supporter_review_flow_backups", primary_key: "supporter_id", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "intake_status"
    t.string "public_review_status"
    t.string "review_status"
    t.index ["supporter_id"], name: "index_dpg_supporter_review_flow_backups_on_supporter_id", unique: true
  end

  create_table "event_rsvps", force: :cascade do |t|
    t.boolean "attended"
    t.datetime "checked_in_at"
    t.integer "checked_in_by_id"
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.string "rsvp_status"
    t.bigint "supporter_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_event_rsvps_on_event_id"
    t.index ["supporter_id"], name: "index_event_rsvps_on_supporter_id"
  end

  create_table "events", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.datetime "created_at", null: false
    t.date "date"
    t.text "description"
    t.string "event_type"
    t.string "location"
    t.string "name"
    t.integer "quota"
    t.string "status"
    t.time "time"
    t.datetime "updated_at", null: false
    t.bigint "village_id"
    t.index ["campaign_id"], name: "index_events_on_campaign_id"
    t.index ["date"], name: "index_events_on_date"
    t.index ["event_type"], name: "index_events_on_event_type"
    t.index ["status"], name: "index_events_on_status"
    t.index ["village_id"], name: "index_events_on_village_id"
  end

  create_table "gec_import_changes", force: :cascade do |t|
    t.integer "birth_year"
    t.string "change_type", null: false
    t.datetime "created_at", null: false
    t.jsonb "details", default: {}, null: false
    t.date "dob"
    t.string "first_name"
    t.bigint "gec_import_id", null: false
    t.string "last_name"
    t.string "middle_name"
    t.string "previous_village_name"
    t.integer "row_number"
    t.datetime "updated_at", null: false
    t.string "village_name"
    t.string "voter_registration_number"
    t.index "lower((first_name)::text) gin_trgm_ops", name: "idx_gec_import_changes_first_name_trgm", using: :gin
    t.index "lower((last_name)::text) gin_trgm_ops", name: "idx_gec_import_changes_last_name_trgm", using: :gin
    t.index "lower((previous_village_name)::text) gin_trgm_ops", name: "idx_gec_import_changes_prev_village_trgm", using: :gin
    t.index "lower((village_name)::text) gin_trgm_ops", name: "idx_gec_import_changes_village_name_trgm", using: :gin
    t.index "lower((voter_registration_number)::text) gin_trgm_ops", name: "idx_gec_import_changes_vrn_trgm", using: :gin
    t.index ["gec_import_id", "change_type"], name: "index_gec_import_changes_on_gec_import_id_and_change_type"
    t.index ["voter_registration_number"], name: "index_gec_import_changes_on_voter_registration_number"
  end

  create_table "gec_import_skipped_rows", force: :cascade do |t|
    t.integer "birth_year"
    t.jsonb "corrected_values", default: {}, null: false
    t.datetime "created_at", null: false
    t.date "dob"
    t.string "first_name"
    t.bigint "gec_import_id", null: false
    t.string "last_name"
    t.string "message", null: false
    t.string "middle_name"
    t.jsonb "raw_values", default: [], null: false
    t.string "resolution_action"
    t.jsonb "resolution_details", default: {}, null: false
    t.string "resolution_status", default: "pending", null: false
    t.datetime "resolved_at"
    t.bigint "resolved_by_user_id"
    t.bigint "resolved_gec_voter_id"
    t.integer "row_number", null: false
    t.string "source_name"
    t.datetime "updated_at", null: false
    t.string "village_name"
    t.string "voter_registration_number"
    t.index ["gec_import_id", "resolution_status"], name: "index_gec_import_skipped_rows_on_import_and_status"
    t.index ["gec_import_id", "row_number"], name: "index_gec_import_skipped_rows_on_import_and_row", unique: true
    t.index ["resolved_by_user_id"], name: "index_gec_import_skipped_rows_on_resolved_by_user_id"
    t.index ["resolved_gec_voter_id"], name: "index_gec_import_skipped_rows_on_resolved_gec_voter_id"
  end

  create_table "gec_import_uploads", force: :cascade do |t|
    t.string "content_type"
    t.datetime "created_at", null: false
    t.binary "file_data"
    t.string "file_s3_key"
    t.string "filename", null: false
    t.bigint "gec_import_id", null: false
    t.datetime "updated_at", null: false
    t.index ["file_s3_key"], name: "index_gec_import_uploads_on_file_s3_key"
    t.index ["gec_import_id"], name: "index_gec_import_uploads_on_gec_import_id", unique: true
  end

  create_table "gec_imports", force: :cascade do |t|
    t.datetime "activated_for_election_at"
    t.bigint "activated_for_election_by_user_id"
    t.boolean "active_election_day", default: false, null: false
    t.integer "ambiguous_dob_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.date "gec_list_date", null: false
    t.string "import_type", default: "full_list", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "new_records", default: 0, null: false
    t.string "original_content_type"
    t.string "original_file_s3_key"
    t.string "original_filename"
    t.string "raw_content_type"
    t.string "raw_file_s3_key"
    t.string "raw_filename"
    t.integer "re_vetted_count", default: 0, null: false
    t.integer "removed_records", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.integer "total_records", default: 0, null: false
    t.integer "transferred_records", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "updated_records", default: 0, null: false
    t.bigint "uploaded_by_user_id"
    t.index ["active_election_day"], name: "index_gec_imports_on_active_election_day", unique: true, where: "active_election_day"
    t.index ["gec_list_date"], name: "index_gec_imports_on_gec_list_date"
    t.index ["uploaded_by_user_id"], name: "index_gec_imports_on_uploaded_by_user_id"
  end

  create_table "gec_pdf_previews", force: :cascade do |t|
    t.string "content_type"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.binary "file_data"
    t.string "file_s3_key"
    t.string "filename", null: false
    t.string "preview_request_id", null: false
    t.jsonb "result_data", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_user_id", null: false
    t.index ["file_s3_key"], name: "index_gec_pdf_previews_on_file_s3_key"
    t.index ["preview_request_id"], name: "index_gec_pdf_previews_on_preview_request_id", unique: true
    t.index ["uploaded_by_user_id", "status"], name: "index_gec_pdf_previews_on_uploaded_by_user_id_and_status"
    t.index ["uploaded_by_user_id"], name: "index_gec_pdf_previews_on_uploaded_by_user_id"
  end

  create_table "gec_voters", force: :cascade do |t|
    t.text "address"
    t.integer "birth_year"
    t.datetime "created_at", null: false
    t.date "dob"
    t.boolean "dob_ambiguous", default: false, null: false
    t.string "first_name", null: false
    t.date "gec_list_date", null: false
    t.datetime "imported_at", null: false
    t.string "last_name", null: false
    t.string "middle_name"
    t.bigint "precinct_id"
    t.string "precinct_number"
    t.string "previous_village_name"
    t.bigint "removal_detected_by_import_id"
    t.datetime "removed_at"
    t.string "status", default: "active", null: false
    t.text "turnout_note"
    t.string "turnout_source"
    t.string "turnout_status", default: "not_yet_voted", null: false
    t.datetime "turnout_updated_at"
    t.bigint "turnout_updated_by_user_id"
    t.datetime "updated_at", null: false
    t.bigint "village_id"
    t.string "village_name", null: false
    t.string "voter_registration_number"
    t.index "lower((first_name)::text), lower((last_name)::text), birth_year", name: "index_gec_voters_on_lower_names_and_birth_year"
    t.index "lower((first_name)::text), lower((last_name)::text), dob", name: "index_gec_voters_on_lower_names_and_dob"
    t.index "lower((first_name)::text), lower((last_name)::text), lower((village_name)::text)", name: "index_gec_voters_on_lower_names_and_village"
    t.index ["gec_list_date"], name: "index_gec_voters_on_gec_list_date"
    t.index ["last_name", "first_name", "birth_year"], name: "index_gec_voters_on_name_and_birth_year"
    t.index ["last_name", "first_name", "dob"], name: "index_gec_voters_on_name_and_dob"
    t.index ["precinct_id"], name: "index_gec_voters_on_precinct_id"
    t.index ["removed_at"], name: "index_gec_voters_on_removed_at", where: "(removed_at IS NOT NULL)"
    t.index ["status"], name: "index_gec_voters_on_status"
    t.index ["turnout_status"], name: "index_gec_voters_on_turnout_status"
    t.index ["village_id", "last_name"], name: "index_gec_voters_on_village_and_last_name"
    t.index ["village_id", "precinct_number"], name: "index_gec_voters_on_village_id_and_precinct_number"
    t.index ["village_id"], name: "index_gec_voters_on_village_id"
    t.index ["village_name"], name: "index_gec_voters_on_village_name"
    t.index ["voter_registration_number"], name: "index_gec_voters_on_voter_registration_number"
  end

  create_table "household_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "shared_contact_number"
    t.string "shared_email"
    t.string "street_address"
    t.datetime "updated_at", null: false
    t.bigint "village_id", null: false
    t.index ["shared_contact_number"], name: "index_household_groups_on_shared_contact_number"
    t.index ["village_id"], name: "index_household_groups_on_village_id"
  end

  create_table "poll_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "notes"
    t.bigint "precinct_id", null: false
    t.string "report_type", default: "turnout_update", null: false
    t.datetime "reported_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.integer "voter_count", null: false
    t.index ["precinct_id", "reported_at"], name: "index_poll_reports_on_precinct_id_and_reported_at"
    t.index ["precinct_id"], name: "index_poll_reports_on_precinct_id"
    t.index ["reported_at"], name: "index_poll_reports_on_reported_at"
    t.index ["user_id"], name: "index_poll_reports_on_user_id"
  end

  create_table "poll_watcher_precinct_assignments", force: :cascade do |t|
    t.datetime "assigned_at", null: false
    t.bigint "assigned_by_user_id"
    t.datetime "created_at", null: false
    t.bigint "precinct_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["assigned_by_user_id"], name: "index_poll_watcher_precinct_assignments_on_assigned_by_user_id"
    t.index ["precinct_id"], name: "index_poll_watcher_precinct_assignments_on_precinct_id"
    t.index ["user_id", "precinct_id"], name: "index_poll_watcher_assignments_on_user_and_precinct", unique: true
    t.index ["user_id"], name: "index_poll_watcher_precinct_assignments_on_user_id"
  end

  create_table "precincts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "alpha_range"
    t.datetime "created_at", null: false
    t.string "number"
    t.string "polling_site"
    t.integer "registered_voters"
    t.datetime "updated_at", null: false
    t.bigint "village_id", null: false
    t.index ["active"], name: "index_precincts_on_active"
    t.index ["village_id"], name: "index_precincts_on_village_id"
  end

  create_table "quota_periods", force: :cascade do |t|
    t.bigint "campaign_cycle_id", null: false
    t.datetime "created_at", null: false
    t.date "due_date", null: false
    t.date "end_date", null: false
    t.string "name", null: false
    t.integer "quota_target", default: 6000, null: false
    t.date "start_date", null: false
    t.string "status", default: "open", null: false
    t.jsonb "submission_summary", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_cycle_id", "start_date"], name: "index_quota_periods_on_campaign_cycle_id_and_start_date", unique: true
    t.index ["campaign_cycle_id"], name: "index_quota_periods_on_campaign_cycle_id"
    t.index ["due_date"], name: "index_quota_periods_on_due_date"
    t.index ["status"], name: "index_quota_periods_on_status"
  end

  create_table "quotas", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.datetime "created_at", null: false
    t.bigint "district_id"
    t.string "period"
    t.integer "target_count"
    t.date "target_date"
    t.datetime "updated_at", null: false
    t.bigint "village_id"
    t.index ["campaign_id"], name: "index_quotas_on_campaign_id"
    t.index ["district_id"], name: "index_quotas_on_district_id"
    t.index ["village_id"], name: "index_quotas_on_village_id"
  end

  create_table "referral_codes", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "assigned_user_id"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id"
    t.string "display_name", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "village_id", null: false
    t.index ["assigned_user_id"], name: "index_referral_codes_on_assigned_user_id"
    t.index ["code"], name: "index_referral_codes_on_code", unique: true
    t.index ["created_by_user_id"], name: "index_referral_codes_on_created_by_user_id"
    t.index ["village_id"], name: "index_referral_codes_on_village_id"
  end

  create_table "sms_blasts", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "error_log"
    t.integer "failed_count", default: 0, null: false
    t.jsonb "filters"
    t.integer "initiated_by_user_id"
    t.text "message"
    t.integer "sent_count", default: 0, null: false
    t.datetime "started_at"
    t.string "status"
    t.integer "total_recipients", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["initiated_by_user_id"], name: "index_sms_blasts_on_initiated_by_user_id"
    t.index ["status"], name: "index_sms_blasts_on_status"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "supporter_contact_attempts", force: :cascade do |t|
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.text "note"
    t.string "outcome", null: false
    t.datetime "recorded_at", null: false
    t.bigint "recorded_by_user_id", null: false
    t.bigint "supporter_id", null: false
    t.datetime "updated_at", null: false
    t.index ["outcome"], name: "index_supporter_contact_attempts_on_outcome"
    t.index ["recorded_by_user_id"], name: "index_supporter_contact_attempts_on_recorded_by_user_id"
    t.index ["supporter_id", "recorded_at"], name: "index_contact_attempts_on_supporter_and_recorded_at"
    t.index ["supporter_id"], name: "index_supporter_contact_attempts_on_supporter_id"
  end

  create_table "supporters", force: :cascade do |t|
    t.string "attribution_method", default: "public_signup", null: false
    t.bigint "block_id"
    t.datetime "classified_at"
    t.bigint "classified_by_user_id"
    t.string "contact_classification", default: "new_intake", null: false
    t.string "contact_number"
    t.datetime "created_at", null: false
    t.date "dob"
    t.datetime "duplicate_checked_at"
    t.text "duplicate_notes"
    t.bigint "duplicate_of_id"
    t.string "email"
    t.integer "entered_by_user_id"
    t.string "first_name"
    t.bigint "gec_voter_id"
    t.bigint "household_group_id"
    t.boolean "household_primary", default: false, null: false
    t.string "intake_status", default: "accepted", null: false
    t.string "last_name"
    t.string "leader_code"
    t.string "middle_name"
    t.boolean "motorcade_available"
    t.boolean "needs_absentee_ballot_help", default: false, null: false
    t.boolean "needs_election_day_ride", default: false, null: false
    t.boolean "needs_homebound_voting_help", default: false, null: false
    t.boolean "needs_voter_registration_help", default: false, null: false
    t.string "normalized_phone"
    t.boolean "opt_in_email", default: false, null: false
    t.boolean "opt_in_text", default: false, null: false
    t.boolean "potential_duplicate", default: false, null: false
    t.bigint "precinct_id"
    t.string "print_name"
    t.string "public_review_status", default: "not_applicable", null: false
    t.datetime "public_reviewed_at"
    t.bigint "public_reviewed_by_user_id"
    t.bigint "quota_period_id"
    t.bigint "referral_code_id"
    t.string "referred_by_name"
    t.integer "referred_from_village_id"
    t.boolean "registered_voter"
    t.text "registered_voter_location_note"
    t.string "registered_voter_status", default: "not_sure", null: false
    t.datetime "registration_outreach_date"
    t.text "registration_outreach_notes"
    t.string "registration_outreach_status"
    t.string "review_status", default: "approved", null: false
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_user_id"
    t.boolean "self_reported_registered_voter"
    t.string "source"
    t.string "status"
    t.string "street_address"
    t.bigint "submitted_village_id"
    t.datetime "support_follow_up_date"
    t.text "support_follow_up_notes"
    t.string "support_follow_up_status"
    t.text "turnout_note"
    t.string "turnout_source"
    t.string "turnout_status", default: "not_yet_voted", null: false
    t.datetime "turnout_updated_at"
    t.bigint "turnout_updated_by_user_id"
    t.datetime "updated_at", null: false
    t.string "verification_reason"
    t.jsonb "verification_reason_metadata", default: {}, null: false
    t.string "verification_status", default: "unverified", null: false
    t.datetime "verified_at"
    t.bigint "verified_by_user_id"
    t.bigint "village_id", null: false
    t.boolean "wants_to_volunteer", default: false, null: false
    t.boolean "yard_sign"
    t.index "lower((email)::text)", name: "index_supporters_on_lower_email", where: "(email IS NOT NULL)"
    t.index "lower((print_name)::text) gin_trgm_ops", name: "index_supporters_on_lower_print_name_trgm", using: :gin
    t.index "village_id, lower(TRIM(BOTH FROM first_name)), lower(TRIM(BOTH FROM last_name))", name: "index_supporters_on_village_lower_first_last_name"
    t.index ["attribution_method"], name: "index_supporters_on_attribution_method"
    t.index ["block_id"], name: "index_supporters_on_block_id"
    t.index ["classified_by_user_id"], name: "index_supporters_on_classified_by_user_id"
    t.index ["contact_classification"], name: "index_supporters_on_contact_classification"
    t.index ["contact_number"], name: "index_supporters_on_contact_number_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["created_at"], name: "index_supporters_on_created_at"
    t.index ["duplicate_of_id"], name: "index_supporters_on_duplicate_of_id"
    t.index ["entered_by_user_id"], name: "index_supporters_on_entered_by_user_id"
    t.index ["gec_voter_id"], name: "index_supporters_on_gec_voter_id"
    t.index ["household_group_id"], name: "index_supporters_on_household_group_id"
    t.index ["intake_status"], name: "index_supporters_on_intake_status"
    t.index ["last_name", "first_name"], name: "index_supporters_on_last_name_and_first_name"
    t.index ["last_name"], name: "index_supporters_on_last_name"
    t.index ["leader_code"], name: "index_supporters_on_leader_code"
    t.index ["needs_voter_registration_help"], name: "index_supporters_on_needs_voter_registration_help"
    t.index ["normalized_phone"], name: "index_supporters_on_normalized_phone"
    t.index ["potential_duplicate"], name: "index_supporters_on_potential_duplicate"
    t.index ["precinct_id", "created_at"], name: "index_supporters_on_precinct_id_and_created_at"
    t.index ["precinct_id", "turnout_status"], name: "index_supporters_on_precinct_id_and_turnout_status"
    t.index ["precinct_id"], name: "index_supporters_on_precinct_id"
    t.index ["print_name", "village_id"], name: "index_supporters_on_name_village"
    t.index ["public_review_status"], name: "index_supporters_on_public_review_status"
    t.index ["public_reviewed_by_user_id"], name: "index_supporters_on_public_reviewed_by_user_id"
    t.index ["quota_period_id"], name: "index_supporters_on_quota_period_id"
    t.index ["referral_code_id"], name: "index_supporters_on_referral_code_id"
    t.index ["registered_voter_status"], name: "index_supporters_on_registered_voter_status"
    t.index ["registration_outreach_status"], name: "index_supporters_on_registration_outreach_status"
    t.index ["review_status"], name: "index_supporters_on_review_status"
    t.index ["reviewed_by_user_id"], name: "index_supporters_on_reviewed_by_user_id"
    t.index ["self_reported_registered_voter"], name: "index_supporters_on_self_reported_registered_voter"
    t.index ["source"], name: "index_supporters_on_source"
    t.index ["status", "village_id", "motorcade_available"], name: "idx_on_status_village_id_motorcade_available_edb4af7743"
    t.index ["status", "village_id"], name: "index_supporters_on_status_and_village_id"
    t.index ["status"], name: "index_supporters_on_status"
    t.index ["submitted_village_id"], name: "index_supporters_on_submitted_village_id"
    t.index ["support_follow_up_status"], name: "index_supporters_on_support_follow_up_status"
    t.index ["turnout_status"], name: "index_supporters_on_turnout_status"
    t.index ["turnout_updated_by_user_id"], name: "index_supporters_on_turnout_updated_by_user_id"
    t.index ["verification_reason"], name: "index_supporters_on_verification_reason"
    t.index ["verification_status"], name: "index_supporters_on_verification_status"
    t.index ["verified_by_user_id"], name: "index_supporters_on_verified_by_user_id"
    t.index ["village_id", "created_at"], name: "index_supporters_on_village_id_and_created_at"
    t.index ["village_id"], name: "index_supporters_on_village_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "assigned_block_id"
    t.integer "assigned_district_id"
    t.integer "assigned_village_id"
    t.string "avatar_url"
    t.string "clerk_id", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "first_name"
    t.string "github_username"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "name"
    t.string "phone"
    t.string "role", default: "block_leader", null: false
    t.datetime "updated_at", null: false
    t.index ["clerk_id"], name: "index_users_on_clerk_id", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  create_table "village_quotas", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "quota_period_id", null: false
    t.integer "submitted_count", default: 0
    t.integer "target", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "village_id", null: false
    t.index ["quota_period_id", "village_id"], name: "index_village_quotas_on_quota_period_id_and_village_id", unique: true
    t.index ["quota_period_id"], name: "index_village_quotas_on_quota_period_id"
    t.index ["village_id"], name: "index_village_quotas_on_village_id"
  end

  create_table "villages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "district_id"
    t.string "name"
    t.integer "population"
    t.string "region"
    t.datetime "updated_at", null: false
    t.index ["district_id"], name: "index_villages_on_district_id"
    t.index ["name"], name: "index_villages_on_name", unique: true
  end

  add_foreign_key "audit_logs", "users", column: "actor_user_id"
  add_foreign_key "blocks", "villages"
  add_foreign_key "cable_token_nonces", "users"
  add_foreign_key "districts", "campaigns"
  add_foreign_key "event_rsvps", "events"
  add_foreign_key "event_rsvps", "supporters"
  add_foreign_key "events", "campaigns"
  add_foreign_key "events", "villages"
  add_foreign_key "gec_import_changes", "gec_imports"
  add_foreign_key "gec_import_skipped_rows", "gec_imports"
  add_foreign_key "gec_import_skipped_rows", "gec_voters", column: "resolved_gec_voter_id"
  add_foreign_key "gec_import_skipped_rows", "users", column: "resolved_by_user_id"
  add_foreign_key "gec_import_uploads", "gec_imports"
  add_foreign_key "gec_imports", "users", column: "activated_for_election_by_user_id"
  add_foreign_key "gec_imports", "users", column: "uploaded_by_user_id"
  add_foreign_key "gec_pdf_previews", "users", column: "uploaded_by_user_id"
  add_foreign_key "gec_voters", "precincts"
  add_foreign_key "gec_voters", "users", column: "turnout_updated_by_user_id"
  add_foreign_key "gec_voters", "villages"
  add_foreign_key "household_groups", "villages"
  add_foreign_key "poll_reports", "precincts"
  add_foreign_key "poll_reports", "users"
  add_foreign_key "poll_watcher_precinct_assignments", "precincts"
  add_foreign_key "poll_watcher_precinct_assignments", "users"
  add_foreign_key "poll_watcher_precinct_assignments", "users", column: "assigned_by_user_id"
  add_foreign_key "precincts", "villages"
  add_foreign_key "quota_periods", "campaign_cycles"
  add_foreign_key "quotas", "campaigns"
  add_foreign_key "quotas", "districts"
  add_foreign_key "quotas", "villages"
  add_foreign_key "referral_codes", "users", column: "assigned_user_id"
  add_foreign_key "referral_codes", "users", column: "created_by_user_id"
  add_foreign_key "referral_codes", "villages"
  add_foreign_key "sms_blasts", "users", column: "initiated_by_user_id"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "supporter_contact_attempts", "supporters"
  add_foreign_key "supporter_contact_attempts", "users", column: "recorded_by_user_id"
  add_foreign_key "supporters", "blocks"
  add_foreign_key "supporters", "gec_voters"
  add_foreign_key "supporters", "household_groups"
  add_foreign_key "supporters", "precincts"
  add_foreign_key "supporters", "quota_periods"
  add_foreign_key "supporters", "referral_codes"
  add_foreign_key "supporters", "supporters", column: "duplicate_of_id"
  add_foreign_key "supporters", "users", column: "classified_by_user_id"
  add_foreign_key "supporters", "users", column: "turnout_updated_by_user_id"
  add_foreign_key "supporters", "villages"
  add_foreign_key "supporters", "villages", column: "submitted_village_id"
  add_foreign_key "village_quotas", "quota_periods"
  add_foreign_key "village_quotas", "villages"
  add_foreign_key "villages", "districts"
end
