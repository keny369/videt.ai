Rails.application.routes.draw do
  # Liveness only: 200 if the app boots. Outside every authenticated surface and
  # carrying no product data.
  get "up" => "rails/health#show", as: :rails_health_check

  # WEB-001..WEB-005 (FRONTEND_ARCHITECTURE.md § Unauthenticated and identity screens).
  # Everything under /start is receipt-entry: no Session exists yet, the forms set
  # data-turbo="false", and success is a 303 to the authorized logical destination.
  scope "/start", as: :start do
    get "sign-in", to: "start/sign_ins#new", as: :sign_in
    post "sign-in", to: "start/sign_ins#create"

    get "bootstrap-grant", to: "start/bootstrap_grants#new", as: :bootstrap_grant
    post "bootstrap-grant", to: "start/bootstrap_grants#create"

    get "bootstrap-organization", to: "start/organizations#new", as: :bootstrap_organization
    post "bootstrap-organization", to: "start/organizations#create"
  end

  # The Session-bound product shell. Every route declares the exact capability it needs;
  # none infers one from the controller or action name.
  scope "/app", module: "app", as: :app do
    root to: "home#show", as: :home

    resources :projects, only: %i[index new create] do
      member { post :activate }

      resources :sources, only: %i[index new create] do
        member { post :activate }

        # WF-003 ownership verification. One Source has at most one governing
        # Verification Request, so this is a singular resource: `show` is QRY-021,
        # `create` issues the challenge, `observe` reserves and runs one on-demand
        # observation. `place_record` exists only in an opted-in development process
        # and the action refuses everywhere else.
        resource :verification, only: %i[show create], controller: "verifications" do
          post :observe
          post :place_record
        end
      end

      # `show` is WEB-017 QRY-023 CrawlDetail: what one run actually did.
      resources :crawls, only: %i[index create show]
    end

    # WEB-005: a Session with no effective access has somewhere deterministic to land.
    get "access-unavailable", to: "access#unavailable", as: :access_unavailable
  end

  root to: redirect("/app")
end
