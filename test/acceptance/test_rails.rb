# frozen_string_literal: true

require "open3"

require_relative "acceptance_test"

module PG
  module AzureWorkloadIdentity
    # Acceptance tests covering Rails-specific entry points (e.g.
    # `rails dbconsole`) that shell out to psql via a separate process.
    class TestRails < AcceptanceTest
      def test_rails_dbconsole
        args = [File.expand_path("rails/dbconsole.rb", __dir__)]
        args.unshift("-r", File.expand_path("rails/simplecov.rb", __dir__)) if defined?(SimpleCov) && SimpleCov.running

        stdout, stderr, status = Open3.capture3(
          {
            "DATABASE_URL" => database_url(username: @username, azure_workload_identity: true),
            "PGPASSWORD" => "none",
            "PSQLRC" => File.expand_path("rails/.psqlrc", __dir__),
            "RUBYOPT" => "-W0",
            # The subprocess stubs the AAD endpoint with WebMock and returns
            # this exact token, which matches the postgres user's password.
            "AAD_TEST_ACCESS_TOKEN" => @access_token,
            # Needed for the AuthTokenGenerator.default instance in the
            # subprocess (its `.default` factory reads these via ENV.fetch).
            "AZURE_TENANT_ID" => AZURE_TENANT_ID,
            "AZURE_CLIENT_ID" => AZURE_CLIENT_ID,
            "AZURE_FEDERATED_TOKEN_FILE" => @federated_token_file.path
          },
          RbConfig.ruby,
          *args,
          stdin_data: "SELECT 'success';\n"
        )

        assert_empty stderr
        assert_equal "success\n", stdout
        assert_predicate status, :success?
      end
    end
  end
end
