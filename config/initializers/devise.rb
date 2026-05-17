Devise.setup do |config|
  config.mailer_sender = ENV.fetch("MAILER_SENDER", "no-reply@psyclinic.test")

  require "devise/orm/active_record"

  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]

  # Only skip session storage for HTTP basic auth. Do NOT include
  # :params_auth here — in this devise-jwt + api_only setup it stops the
  # email/password login strategy from authenticating (Warden finds no
  # eligible strategy and 401s with zero DB queries). Token revocation is
  # handled by the JWT denylist, not the session, so this is still stateless.
  config.skip_session_storage = [:http_auth]

  config.stretches = Rails.env.test? ? 1 : 12

  config.reconfirmable = true
  config.expire_all_remember_me_on_sign_out = true
  config.password_length = 8..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
  config.reset_password_within = 6.hours
  config.sign_out_via = :delete

  # Tell Devise we are API-only; responses are JSON, no navigational HTML.
  config.navigational_formats = []

  # ---- JWT (devise-jwt) ----
  config.jwt do |jwt|
    jwt.secret = ENV.fetch("DEVISE_JWT_SECRET_KEY") do
      Rails.application.credentials.dig(:devise_jwt_secret_key) ||
        "dev_only_insecure_jwt_secret_change_me"
    end
    jwt.dispatch_requests = [
      ["POST", %r{^/api/v1/login$}],
      ["POST", %r{^/api/v1/signup$}]
    ]
    jwt.revocation_requests = [
      ["DELETE", %r{^/api/v1/logout$}]
    ]
    jwt.expiration_time = 1.day.to_i
  end

  # devise-jwt registers a :jwt strategy but leaves the :user scope's
  # default strategy order unset, so warden.authenticate! on the login
  # endpoint had no strategy to run and always failed despite valid
  # credentials. This block runs at BOOT (when Warden's manager is
  # configured) — NOT per-request — and uses Devise's documented setter
  # form of default_strategies, which assigns the ordered list rather than
  # mutating a possibly-nil array. Order: email/password first (login),
  # then the JWT token strategy (authenticated requests with a Bearer).
  config.warden do |manager|
    manager.default_strategies(:database_authenticatable, :jwt, scope: :user)
  end
end
