Rails.application.routes.draw do
  # Redirect to localhost from 127.0.0.1 to use same IP address with Vite server
  constraints(host: "127.0.0.1") do
    get "(*path)", to: redirect { |params, req| "#{req.protocol}localhost:#{req.port}/#{params[:path]}" }
  end

  # /account/sign_in, /account/sign_up, /account/password/new, /account/confirmation/new, ...
  devise_for :users, path: "account", controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations",
    passwords: "users/passwords",
    confirmations: "users/confirmations"
  }

  # The emailed confirmation link (GET) only shows a button, for the same reason as sign-in links
  devise_scope :user do
    post "account/confirmation/confirm", to: "users/confirmations#confirm", as: :confirm_user_confirmation
  end

  # Passwordless sign-in: each request emails a one-time link and a six-digit code. The link's
  # GET only shows a confirm button, so link scanners can't use them up.
  scope "account" do
    post "sign_in_link", to: "magic_links#create", as: :magic_links
    get "sign_in_code", to: "magic_links#code", as: :sign_in_code
    post "sign_in_code", to: "magic_links#verify"
    get "sign_in_link/:token", to: "magic_links#show", as: :magic_link
    post "sign_in_link/:token", to: "magic_links#redeem", as: :redeem_magic_link
  end

  resource :settings, only: [:show, :update]
  # The daily digest's settings, with a preview of today's email and a test send
  resource :alerts, only: [:show, :update] do
    post :test_email
  end

  # The daily digest's unsubscribe link. Its GET only shows a button; the POST also takes mail
  # providers' one-click unsubscribe (List-Unsubscribe-Post).
  get "digest/unsubscribe/:token", to: "digest_unsubscribes#show", as: :digest_unsubscribe
  post "digest/unsubscribe/:token", to: "digest_unsubscribes#create"

  # Setup: farms → pivots → fields → plantings, the guided first run, and copying last season
  resource :setup, only: :show, controller: "setup"
  resource :quick_setup, only: [:new, :create], path: "setup/start", path_names: {new: ""}
  resource :season_copy, only: :create, path: "setup/copy_season"
  resources :farms, only: [:create, :update, :destroy]
  resources :pivots, only: [:show, :new, :create, :edit, :update, :destroy] do
    resources :irrigations, only: [:create, :update, :destroy], controller: "pivot_irrigations"
  end
  resources :fields, only: [:show, :create, :update, :destroy] do
    resources :days, only: :update, controller: "field_days", param: :date
  end
  resources :plantings, only: [:create, :update, :destroy] do
    get :export, on: :member, defaults: {format: :csv}
  end
  resources :field_groups, only: [:index, :show, :create, :update, :destroy] do
    resources :days, only: :update, controller: "field_group_days", param: :date
  end
  resource :daily_entry, only: [:show, :update], path: "daily"

  namespace :admin do
    resources :users, only: [:index, :show, :destroy] do
      get :digest, on: :member
    end
    resource :weather, only: :show, controller: "weather" do
      post :refresh
    end
  end
  resource :current_group, only: :update, path: "group"
  # The current farm operation (Current.group) and its members; creating another
  resource :group, only: [:show, :update, :destroy], path: "operation"
  resources :groups, only: :create, path: "operations"
  resources :memberships, only: [:create, :update, :destroy], path: "operation/members"

  root "dashboard#show"

  get "up", to: "rails/health#show", as: :rails_health_check

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
    # Chrome DevTools asks every localhost site for its workspace settings; answer so it isn't logged
    # as a routing error
    get ".well-known/appspecific/com.chrome.devtools.json", to: proc { [204, {}, []] }
  end
end
