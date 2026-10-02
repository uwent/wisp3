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

  # One-time sign-in links. GET only shows a confirm button, so link scanners can't use them up.
  scope "account" do
    post "sign_in_link", to: "magic_links#create", as: :magic_links
    get "sign_in_link/:token", to: "magic_links#show", as: :magic_link
    post "sign_in_link/:token", to: "magic_links#redeem", as: :redeem_magic_link
  end

  resource :settings, only: [:show, :update]
  resource :current_group, only: :update, path: "group"

  root "dashboard#show"

  get "up", to: "rails/health#show", as: :rails_health_check

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
end
