source "https://rubygems.org"

ruby "3.1.0"

gem "rails", "7.1.3.4"
gem "pg", "~> 1.5"
gem "puma", "~> 6.4"

# Auth
gem "devise", "~> 4.9"
gem "devise-jwt", "~> 0.11.0"

# Authorization
gem "cancancan", "~> 3.5"

# JSON serialization
gem "active_model_serializers", "~> 0.10.14"

# CORS for the future frontend
gem "rack-cors", "~> 2.0"

gem "bootsnap", require: false
gem "tzinfo-data", platforms: %i[windows jruby]

group :development, :test do
  gem "debug", platforms: %i[mri windows]
  gem "rspec-rails", "~> 6.1"
  gem "factory_bot_rails", "~> 6.4"
end

group :development do
  gem "listen", "~> 3.8"
end
