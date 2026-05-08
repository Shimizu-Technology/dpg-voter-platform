Rails.application.routes.draw do
  mount ActionCable.server => "/cable"
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      # Public
      get "campaign_info", to: "campaign_info#show"
      get "session", to: "session#show"
      get "dashboard", to: "dashboard#show"
      get "stats", to: "dashboard#stats"
      resource :settings, only: [ :show, :update ]
      resources :villages, only: [ :index, :show ]
      resources :districts, only: [ :index, :create, :update, :destroy ] do
        member do
          patch :assign_villages
        end
      end
      resources :supporters, only: [ :create, :index, :show, :update ] do
        member do
          patch :verify
          patch :revet
          patch :resolve_duplicate
          patch :outreach_status
          patch :accept_to_quota
          patch :reject_public_review
          patch :approve_supporter
          patch :reject_supporter
        end
        collection do
          get :check_duplicate
          get :export
          get :duplicates
          get :outreach
          get :public_review
          get :vetting_queue
          post :bulk_verify
          post :bulk_revet
          post :scan_duplicates
        end
      end
      resources :users, only: [ :index, :create, :update, :destroy ] do
        member do
          post :resend_invite
        end
      end
      resources :quotas, only: [ :index, :update ], param: :village_id
      resources :precincts, only: [ :index, :update ]
      resources :audit_logs, only: [ :index ]

      # Authenticated staff
      namespace :staff do
        resources :supporters, only: [ :create ]
      end

      # War Room
      get "war_room", to: "war_room#index"
      post "war_room/supporters/:supporter_id/contact_attempts", to: "war_room#create_contact_attempt"

      # Poll Watcher
      get "poll_watcher", to: "poll_watcher#index"
      post "poll_watcher/report", to: "poll_watcher#report"
      get "poll_watcher/precinct/:id/history", to: "poll_watcher#history"
      get "poll_watcher/strike_list", to: "poll_watcher#strike_list"
      patch "poll_watcher/strike_list/:voter_id/turnout", to: "poll_watcher#update_turnout"

      # Leaderboard
      get "leaderboard", to: "leaderboard#index"

      # QR Codes
      resources :qr_codes, only: [ :show ] do
        member do
          get :info
        end
        collection do
          get :assignees
          post :generate
        end
      end

      # Bulk Import
      post "imports/preview", to: "imports#preview"
      post "imports/parse", to: "imports#parse"
      post "imports/confirm", to: "imports#confirm"

      # Reports (Excel export)
      get "reports", to: "reports#index"
      get "reports/:report_type/preview", to: "reports#preview"
      get "reports/:report_type", to: "reports#show"

      # Campaign Cycles & Quota Periods
      resources :campaign_cycles, only: %i[index create update destroy] do
        collection do
          get :current
        end
      end
      resources :quota_periods, only: %i[show update] do
        member do
          post :submit
          get :village_quotas
          patch :village_quotas, action: :update_village_quotas
        end
      end

      # GEC Voter List
      resources :gec_voters, only: [ :index ] do
        collection do
          get :stats
          get :imports
          get :preview_status
          get "imports/:id/view_data", action: :view_import_data, as: :view_import_data
          get "imports/:id/changes", action: :view_import_changes, as: :view_import_changes
          get "imports/:id/skipped_rows", action: :view_import_skipped_rows, as: :view_import_skipped_rows
          post "imports/:id/activate_election_day", action: :activate_election_day_import, as: :activate_election_day_import
          post "imports/:id/skipped_rows/:skipped_row_id/preview_resolution", action: :preview_skipped_row_resolution, as: :preview_skipped_row_resolution
          post "imports/:id/skipped_rows/:skipped_row_id/resolve", action: :resolve_skipped_row, as: :resolve_skipped_row
          post "imports/:id/skipped_rows/:skipped_row_id/dismiss", action: :dismiss_skipped_row, as: :dismiss_skipped_row
          get "imports/:id/view_original", action: :view_original, as: :view_original
          get "imports/:id/download", action: :download_import, as: :download_import
          post :upload
          post :preview
          post :match
          post :bulk_vet
        end
      end

      # Form Scanner (OCR)
      post "scan", to: "scan#create"
      post "scan/batch", to: "scan#batch"
      post "scan/telemetry", to: "scan#telemetry"

      # SMS
      get "sms/status", to: "sms#status"
      post "sms/send", to: "sms#send_single"
      post "sms/blast", to: "sms#blast"
      post "sms/event_notify", to: "sms#event_notify"
      get "sms/blasts", to: "sms#blasts"
      get "sms/blasts/:id", to: "sms#blast_status"

      # Email
      get "email/status", to: "email#status"
      post "email/blast", to: "email#blast"

      # Events
      resources :events, only: [ :index, :show, :create ] do
        member do
          post :check_in
          get :attendees
          post :send_sms
          post :send_email
        end
      end
    end
  end

  root to: proc { [ 200, {}, [ "Campaign Tracker API v1.0" ] ] }
end
