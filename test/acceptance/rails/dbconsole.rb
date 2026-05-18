# frozen_string_literal: true

require "logger"
require "bundler/setup"

# Stub the Azure AD token endpoint before anything in the gem makes an
# outbound HTTP request. The parent test process passes
# AAD_TEST_ACCESS_TOKEN — that's the value the stubbed endpoint returns,
# which is also the password the test postgres user was created with, so
# psql authenticates cleanly when Rails::DBConsole execs it.
require "webmock"
require "json"
WebMock.enable!
WebMock::API.stub_request(
  :post,
  "https://login.microsoftonline.com/#{ENV.fetch("AZURE_TENANT_ID")}/oauth2/v2.0/token"
).to_return(
  status: 200,
  headers: { "Content-Type" => "application/json" },
  body: JSON.generate(
    token_type: "Bearer",
    expires_in: 3600,
    access_token: ENV.fetch("AAD_TEST_ACCESS_TOKEN")
  )
)

require "rails"
require "rails/command"
require "rails/commands/dbconsole/dbconsole_command"
require "active_record"

APP_PATH = File.expand_path("application", __dir__)

Rails::DBConsole.start
