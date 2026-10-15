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

  # Notes and folders share the move and sharing pages. Each GET shows the page and the PATCH
  # submits it. All the routes are defined here up front; their actions are added as they are built.
  concern :movable_and_shareable do
    member do
      get :move
      patch :move, action: :update_move
      get :sharing
      patch :sharing, action: :update_sharing
    end
  end

  resources :notes, only: [ :show, :new, :create, :edit, :update, :destroy ], concerns: :movable_and_shareable
  resources :folders, only: [ :show, :new, :create, :edit, :update, :destroy ], concerns: :movable_and_shareable
  resources :shares, only: [ :create, :update, :destroy ]
end
