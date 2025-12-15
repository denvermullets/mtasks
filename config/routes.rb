Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resources :users, only: %i[new create]
  resources :teams, only: %i[new create show] do
    resources :issues
  end

  # CSV Import
  resources :imports, only: %i[new create]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root to: redirect { |_params, request|
    team_id = request.session[:current_team_id]
    team_id ? "/teams/#{team_id}/issues" : '/teams/new'
  }
end
