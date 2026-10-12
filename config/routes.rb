Rails.application.routes.draw do
  root "home#index"
  get "welcome", to: "accounts#new", as: :welcome
  resource :account, only: %i[create show destroy]
  get "access/:access_token", to: "accounts#access", as: :access
  post "access/:access_token", to: "accounts#enter", as: :enter_access

  resources :sessions, only: [] do
    collection do
      get :next, action: :next_question
      get :complete
    end
  end

  resources :reviews, only: [ :create ]

  resource :diagnostic, only: [ :show ], controller: "diagnostic" do
    post :answer, on: :collection
  end

  resource :settings, only: %i[show update], controller: "settings"

  get "progress", to: "progress#index"
  get "progress/:character", to: "progress#show", as: :progress_kanji

  resources :suspensions, only: %i[create destroy]
  resources :graduations, only: %i[destroy]
  resources :knownness, only: %i[create]
  resource :reading, only: [ :show ], controller: "reading" do
    post :complete, on: :collection
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
