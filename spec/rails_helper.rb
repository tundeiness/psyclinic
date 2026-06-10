require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("Rails is running in production mode!") if Rails.env.production?
require "rspec/rails"

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods

  # Build a Bearer header by encoding a JWT directly for the user — the
  # documented way to test devise-jwt. This deliberately avoids hitting
  # the login endpoint: request specs share one integration session, and
  # a login POST sets a session cookie that Warden would deserialize on
  # later requests, making every request act as whoever logged in first.
  # Encoding the token directly tests the real authorization path
  # (controllers + abilities) with identity coming solely from the token.
  config.include(Module.new do
    def auth_header_for(user)
      token, _payload = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
      { "Authorization" => "Bearer #{token}" }
    end
  end, type: :request)

  # Phase 8 introduced a signed-contract gate on PurchaseSessionBlock.
  # Specs that test block-purchase logic in isolation need a quick way
  # to satisfy that gate without going through the full contract-signing
  # flow. This helper creates a valid electronic contract for the given
  # client at the current version.
  config.include(Module.new do
    def sign_contract_for!(client_profile)
      ClientContract.create!(
        client_profile: client_profile,
        contract_version: AppSetting.current.current_contract_version,
        signature_method: :electronic,
        signed_at: Time.current,
        electronic_signature_name: client_profile.full_name
      )
    end
  end)
end
