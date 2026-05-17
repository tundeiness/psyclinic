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
end
