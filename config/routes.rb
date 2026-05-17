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

      # --- Admin (Head-Therapist) management surface ---
      namespace :admin do
        resources :clients, only: %i[index show destroy]
        resources :therapists, only: %i[index show create destroy]
        resources :specializations, only: %i[index create destroy]
        resources :therapist_specializations, only: %i[create destroy]
        resources :pairings, only: %i[index create destroy]
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
      end
    end
  end

  get "up", to: "rails/health#show", as: :rails_health_check
end
