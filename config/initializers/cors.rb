Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("CORS_ORIGINS", "http://localhost:3000,http://localhost:5173").split(",")

    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      # Expose the Authorization header so the frontend can read the
      # JWT that devise-jwt sets on login.
      expose: %w[Authorization],
      max_age: 600
  end
end
