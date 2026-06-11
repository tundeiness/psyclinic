Rails.application.routes.draw do
  # devise_for is intentionally NOT nested inside `namespace :api/:v1`.
  # Nesting it makes Devise build the mapping as :api_v1_user, so the
  # generated helpers become `authenticate_api_v1_user!` /
  # `current_api_v1_user` — but every controller calls the plain
  # `authenticate_user!` / `current_user`. Declaring it at top level with
  # an explicit path keeps the :user scope (correct helper names) while
  # still serving the routes under /api/v1/...
  devise_for :users,
    path: "api/v1",
    path_names: {
      sign_in: "login",
      sign_out: "logout",
      registration: "signup"
    },
    controllers: {
      sessions: "api/v1/users/sessions",
      registrations: "api/v1/users/registrations"
    }

  namespace :api do
    namespace :v1 do
      get "me", to: "profiles#me"

      # Current user's avatar & documents (Active Storage).
      put    "me/avatar",        to: "avatars#update"
      delete "me/avatar",        to: "avatars#destroy"
      get    "me/documents",     to: "documents#index"
      post   "me/documents",     to: "documents#create"
      delete "me/documents/:id", to: "documents#destroy"

      # Blog posts authoring (auth required; CanCanCan gates each action).
      resources :blog_posts, only: %i[index show create update destroy] do
        resources :images, only: %i[create destroy],
                  controller: "blog_images"
      end

      # --- Public (unauthenticated) welcome page ---
      namespace :public do
        resources :therapists, only: %i[index show]
        resources :blog_posts, only: %i[index show]
        get :pricing, to: "pricing#show"
      end

      # --- Admin (Head-Therapist) management surface ---
      namespace :admin do
        get "dashboard", to: "dashboard#show"
        resources :applications, only: %i[index] do
          member do
            patch :approve
            patch :reject
          end
        end
        get   "settings", to: "settings#show"
        patch "settings", to: "settings#update"
        resources :clients, only: %i[index show destroy]
        resources :therapists, only: %i[index show create destroy] do
          member do
            patch :promote_co_admin
            patch :demote_co_admin
          end
        end
        resources :specializations, only: %i[index create destroy]
        resources :therapist_specializations, only: %i[create destroy]
        resources :availability_slots, only: %i[index update] do
          member do
            patch :approve
            patch :reject
          end
        end
      end

      # Phase 8: contract certification queue. Lives outside the admin
      # namespace because regular therapists (not just admins/co-admins)
      # need to be able to certify uploads — the admin namespace gates
      # everything behind the admin-panel ability.
      namespace :staff do
        get  "contracts/pending",      to: "contracts#pending"
        post "contracts/:id/certify",  to: "contracts#certify"
        get  "contracts/:id/document", to: "contracts#document"
      end

      # --- Therapist surface ---
      namespace :therapist do
        resources :clients, only: %i[index show]
        resources :availability_slots, only: %i[index create update destroy]
        resources :appointments, only: %i[index show update]
      end

      # --- EMR clinical records (therapist + admin) ---
      # Mounted outside role namespaces because both therapists (with a
      # relationship to the client) and admins use the same endpoints.
      # CanCanCan in the controller decides who can see/edit/sign.
      # URL shape: /api/v1/clients/:client_id/intake_form
      scope "clients/:client_id" do
        # Singular resource — one intake form per client.
        resource :intake_form, only: %i[show create update], controller: "intake_forms" do
          post :sign
          # Phase 15: PDF export. Watermarked when unsigned.
          get :pdf
        end
      end

      # Phase 11: session notes — one per appointment, therapist-authored,
      # signed-and-locked. URL shape:
      #   /api/v1/appointments/:appointment_id/session_note
      scope "appointments/:appointment_id" do
        resource :session_note, only: %i[show create update],
          controller: "session_notes" do
          post :sign
          # Phase 15: PDF export. Watermarked when unsigned.
          get :pdf
        end
      end

      # --- Client surface ---
      namespace :client do
        # Bookable approved slots, optionally filtered by therapist.
        resources :availability_slots, only: %i[index]
        resources :appointments, only: %i[index show create destroy]
        resources :payments, only: %i[show] do
          member { post :confirm }
        end
        # v2: block purchases.
        resources :session_blocks, only: %i[index create] do
          member { post :pay_installment }
        end

        # Phase 8: client services contract (one-time signed).
        get  "contracts/current",  to: "contracts#current"
        get  "contracts/document", to: "contracts#document"
        post "contracts/sign",     to: "contracts#sign"
        post "contracts/upload",   to: "contracts#upload"

        # Phase 14: therapist switching.
        get  "therapist_switches/preview", to: "therapist_switches#preview"
        post "therapist_switches",         to: "therapist_switches#create"
      end

      # --- Stripe webhooks (real Stripe; also receives dev mock events
      #     when they're dispatched server-side via the mock gateway
      #     controller below). Unauthenticated; signature-verified.
      namespace :webhooks do
        post :stripe, to: "stripe#receive"
      end

      # --- Dev-only mock checkout simulator. Frontend mock checkout
      #     page POSTs here with action: succeed | fail. Only routes
      #     are registered outside production; the controller also
      #     guards against being hit in production as defense in depth.
      unless Rails.env.production?
        namespace :dev do
          post "mock_gateway/:payment_intent_id/simulate",
            to: "mock_gateway#simulate"
        end
      end
    end
  end

  get "up", to: "rails/health#show", as: :rails_health_check

  # Unknown API routes -> consistent 404 JSON (not Rails' HTML page).
  # Scoped to /api so Active Storage (/rails/...) and /up are unaffected.
  # Declared last so it only catches genuinely unmatched API paths.
  match "/api/*unmatched", to: "application#route_not_found", via: :all
end
