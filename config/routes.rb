Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "notes#index"

  resource :current_user, only: :update
  resources :users, only: [ :index, :create ]
  resources :teams, only: [ :index, :show, :create, :edit, :update ] do
    resources :memberships, only: [ :create, :destroy ]
  end

  # Notes and folders share the sharing page. The GET shows the page and the PATCH submits it.
  concern :shareable do
    member do
      get :sharing
      patch :sharing, action: :update_sharing
    end
  end

  resources :notes, only: [ :show, :new, :create, :edit, :update, :destroy ], concerns: :shareable
  resources :folders, only: [ :show, :new, :create, :edit, :update, :destroy ], concerns: :shareable
  resources :shares, only: [ :create, :update, :destroy ]

  # The JSON REST API (see API.md). The current user comes from the X-User-Id header.
  namespace :api, defaults: { format: :json } do
    resources :users, only: [ :index, :show, :create ]
    resources :teams, only: [ :index, :show, :create, :update ] do
      resources :members, only: [ :create, :destroy ], param: :user_id
    end
    get "home" => "home#show"
    resources :folders, only: [ :index, :show, :create, :update, :destroy ] do
      resources :shares, only: [ :index, :create ]
    end
    resources :notes, only: [ :index, :show, :create, :update, :destroy ] do
      resources :shares, only: [ :index, :create ]
    end
    resources :shares, only: [ :update, :destroy ]
  end
end
