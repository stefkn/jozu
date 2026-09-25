Rails.application.routes.draw do
  root "home#index"

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

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
