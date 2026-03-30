Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resources :users, only: %i[new create]
  resource :profile, only: [:update]
  resources :workspaces, only: [] do
    resource :github_installation, only: %i[show new destroy], controller: 'workspace_github_installations' do
      get :callback, on: :collection
    end
  end

  resources :teams, only: %i[new create show edit update] do
    member do
      get :confirm_archive
      delete :archive
    end
    resource :display_preference, only: %i[update]
    # GitHub repositories management
    resources :github_repositories, only: %i[index create destroy], controller: 'team_github_repositories'
    resources :labels, only: %i[index create update destroy]
    resources :milestones, only: %i[index create update destroy]
    resources :lanes, only: %i[create update destroy]
    resources :projects
    resources :team_invitations, only: %i[index create destroy] do
      delete :remove_member, on: :collection
    end
    resources :issues do
      resources :comments, only: %i[create destroy]
      resources :issue_labels, only: %i[create destroy]
    end
  end

  resources :notifications, only: [:index] do
    member { patch :mark_as_read }
    collection { patch :mark_all_as_read }
  end

  # Token-based invitation acceptance (no auth required)
  resources :invitations, only: %i[show update], param: :token, controller: 'invitation_acceptances'

  # CSV Import
  resources :imports, only: %i[new create]

  # GitHub App Installation Callbacks
  get '/github/callback', to: 'workspace_github_installations#callback'

  # API
  namespace :api do
    namespace :v1 do
      resources :teams, only: [:index] do
        resources :issues, only: %i[index show create update]
        resources :lanes, only: [:index]
        resources :labels, only: [:index]
        resources :projects, only: [:index]
        resources :members, only: [:index]
      end
    end
  end

  # API Token management (web UI)
  resources :api_tokens, only: %i[index create destroy]

  # GitHub Webhooks
  namespace :webhooks do
    resource :github, only: [:create], controller: 'github'
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Landing page
  get 'landing', to: 'landing#index'

  # Defines the root path route ("/")
  root to: redirect { |_params, request|
    # Check if user is authenticated by looking for session cookie
    session_id = request.cookie_jar.signed[:session_id]
    session = session_id && Session.find_by(id: session_id)
    if session
      user = session.user
      # Try session team_id first, then fall back to user's first team
      team_id = request.session[:current_team_id]
      team_id ||= user.teams.first&.id
      team_id ? "/teams/#{team_id}/issues" : '/teams/new'
    else
      '/landing'
    end
  }
end
