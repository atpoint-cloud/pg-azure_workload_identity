# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in pg-azure_workload_identity.gemspec
gemspec

gem "rake"

group :development do
  gem "irb"
  gem "overcommit", require: false
end

group :lint do
  gem "rbs"
  gem "rubocop"
  gem "rubocop-minitest"
  gem "rubocop-rake"
  gem "steep"
end

group :test do
  gem_version = lambda do |gem_name|
    ENV["#{gem_name.upcase}_VERSION"]&.then { |gem_version| "~> #{gem_version}.0" }
  end

  gem "activerecord", *gem_version["activerecord"]
  gem "pg", *gem_version["pg"]
  gem "railties", *gem_version["activerecord"]

  gem "minitest"
  gem "minitest-reporters"
  gem "simplecov", require: false
  gem "timecop"
  gem "webmock"
end

group :docs do
  gem "redcarpet"
  gem "webrick"
  gem "yard"
end
