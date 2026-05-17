require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module PsyClinic
  class Application < Rails::Application
    config.load_defaults 7.1

    # API-only: no views, helpers, cookies middleware by default.
    config.api_only = true

    # We use JWT in the Authorization header, so sessions are stateless.
    # Devise/Warden still needs cookie + session middleware present, and
    # CRITICALLY it must sit BEFORE Warden in the stack. `config.middleware.use`
    # appends to the END (after Warden) which breaks Devise auth in api_only
    # mode. Insert it before Warden::Manager instead.
    config.session_store :cookie_store, key: "_psyclinic_session"
    config.middleware.insert_before Warden::Manager, ActionDispatch::Cookies
    config.middleware.insert_before Warden::Manager, ActionDispatch::Session::CookieStore,
      config.session_options

    config.autoload_lib(ignore: %w[assets tasks])

    config.generators do |g|
      g.test_framework :rspec, fixtures: true
      g.fixture_replacement :factory_bot, dir: "spec/factories"
      g.factory_bot suffix: "factory"
    end

    config.active_job.queue_adapter = :async
  end
end
