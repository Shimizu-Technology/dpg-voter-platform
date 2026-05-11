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
          patch :resolve_duplicate
          patch :outreach_status
        end
        collection do
          get :check_duplicate
          get :export
          get :duplicates
          get :outreach
          post :bulk_verify
          post :scan_duplicates
        end
      end
      resources :users, only: [ :index, :create, :update, :destroy ] do
        member do
          post :resend_invite
        end
      end
      resources :precincts, only: [ :index, :update ]
      resources :audit_logs, only: [ :index ]

      # Authenticated staff
      post "staff/supporters", to: "staff_supporters#create"





      # Bulk Import
      post "imports/preview", to: "imports#preview"
      post "imports/parse", to: "imports#parse"
      post "imports/confirm", to: "imports#confirm"

      # Reports (Excel export)
      get "reports", to: "reports#index"
      get "reports/:report_type/preview", to: "reports#preview"
      get "reports/:report_type", to: "reports#show"

      # SMS/email outreach is DPG-scoped and live sends are gated in controllers.
      get "sms/status", to: "sms#status"
      post "sms/send", to: "sms#send_single"
      post "sms/blast", to: "sms#blast"
      get "sms/blasts", to: "sms#blasts"
      get "sms/blasts/:id", to: "sms#blast_status"
      get "email/status", to: "email#status"
      post "email/blast", to: "email#blast"
    end
  end

  root to: proc { [ 200, {}, [ "Democratic Party of Guam Voter Engagement API" ] ] }
end
