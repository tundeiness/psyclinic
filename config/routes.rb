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

      # --- Therapist surface ---
      namespace :therapist do
        resources :clients, only: %i[index show]
        resources :availability_slots, only: %i[index create update destroy]
        resources :appointments, only: %i[index show update]
      end

      # --- Client surface ---
      namespace :client do
        # Bookable approved slots, optionally filtered by therapist.
        resources :availability_slots, only: %i[index]
        resources :appointments, only: %i[index show create destroy]
        resources :payments, only: %i[show] do
          member { post :confirm }
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
