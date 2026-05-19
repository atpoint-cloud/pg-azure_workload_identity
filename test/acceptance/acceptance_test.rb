# frozen_string_literal: true

require "securerandom"
require "tempfile"

require_relative "support/docker_compose"

require "test_helper"

module PG
  module AzureWorkloadIdentity
    # Base class for acceptance tests. Brings up postgres on demand,
    # creates a per-test postgres user with a known password, stubs the
    # Azure AD token endpoint to return that same password, and points the
    # gem at the stubbed endpoint. Subclasses just define the tests; the
    # plumbing is shared.
    #
    # The trick that makes this work without any real AAD: postgres only
    # validates that the password the client sends matches what was stored
    # — it doesn't care whether the string is a JWT or random bytes. So we
    # generate a random "access token", store it as the user's password,
    # and have WebMock hand it back from the AAD stub.
    #
    # Requires postgres running locally — bring it up with:
    #
    #   docker compose -f docker-compose.test.yml up -d
    class AcceptanceTest < Minitest::Test
      AZURE_TENANT_ID = "test-tenant"
      AZURE_CLIENT_ID = "test-client"
      AAD_TOKEN_URL = "https://login.microsoftonline.com/#{AZURE_TENANT_ID}/oauth2/v2.0/token".freeze

      POSTGRES_HOST = ENV.fetch("POSTGRES_HOST", "127.0.0.1")
      POSTGRES_PORT = Integer(ENV.fetch("POSTGRES_PORT", "25432"))
      POSTGRES_DB = ENV.fetch("POSTGRES_DB", "workload_identity_test")
      POSTGRES_SUPERUSER = ENV.fetch("POSTGRES_SUPERUSER", "postgres")
      POSTGRES_SUPERPASS = ENV.fetch("POSTGRES_SUPERPASS", "postgres")

      # Tear down anything we brought up at suite end. `stop_if_started` is
      # a no-op when postgres was already running before the suite started.
      Minitest.after_run { AcceptanceSupport::DockerCompose.stop_if_started }

      def setup
        super
        # Idempotent: short-circuits if postgres is already reachable.
        AcceptanceSupport::DockerCompose.ensure_running!(
          host: POSTGRES_HOST,
          port: POSTGRES_PORT,
          user: POSTGRES_SUPERUSER,
          password: POSTGRES_SUPERPASS,
          dbname: POSTGRES_DB
        )
        skip_unless_postgres_available!

        # The token value is shared by both sides of the contract: postgres
        # stores it as the user's password, WebMock hands it out from the
        # stubbed AAD token endpoint.
        @access_token = "test.token.#{SecureRandom.hex(16)}"
        @username = "app_#{SecureRandom.hex(4)}"

        create_postgres_user(@username, @access_token)

        # Stub the AAD token endpoint. WebMock's per-test reset (via the
        # webmock/minitest teardown alias chain) clears the registry between
        # tests, so request-count assertions don't leak across tests.
        stub_request(:post, AAD_TOKEN_URL).to_return(
          status: 200,
          headers: { "Content-Type" => "application/json; charset=utf-8" },
          body: {
            token_type: "Bearer",
            expires_in: 3600,
            ext_expires_in: 3600,
            access_token: @access_token
          }.to_json
        )

        @federated_token_file = Tempfile.new("federated_token")
        @federated_token_file.write("fake.federated.jwt")
        @federated_token_file.close

        # Point the gem at the stubbed AAD URL.
        @original_generator = AzureWorkloadIdentity.instance_variable_get(:@auth_token_generator)
        AzureWorkloadIdentity.auth_token_generator = AuthTokenGenerator.new(
          identity_endpoint: AAD_TOKEN_URL,
          client_id: AZURE_CLIENT_ID,
          scope: "test-scope",
          grant_type: "client_credentials",
          client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
          federated_token_file: @federated_token_file.path
        )
      end

      def teardown
        @federated_token_file&.unlink
        drop_postgres_user(@username) if @username
        AzureWorkloadIdentity.instance_variable_set(:@auth_token_generator, @original_generator)
        @superuser_connection&.close
        super
      end

      private

      def database_url(username:, password: nil, azure_workload_identity: false)
        URI.for(
          "postgresql",
          password ? "#{username}:#{password}" : username,
          POSTGRES_HOST,
          POSTGRES_PORT,
          nil,
          POSTGRES_DB,
          nil,
          azure_workload_identity ? "azure_workload_identity=true" : nil,
          nil,
          default: URI::HTTP
        ).to_s
      end

      def superuser_connection
        @superuser_connection ||= PG.connect(
          host: POSTGRES_HOST,
          port: POSTGRES_PORT,
          dbname: POSTGRES_DB,
          user: POSTGRES_SUPERUSER,
          password: POSTGRES_SUPERPASS
        )
      end

      def create_postgres_user(username, password)
        ident = superuser_connection.quote_ident(username)
        literal = superuser_connection.escape_literal(password)
        superuser_connection.exec("CREATE USER #{ident} WITH PASSWORD #{literal}")
      end

      def drop_postgres_user(username)
        superuser_connection.exec("DROP USER IF EXISTS #{superuser_connection.quote_ident(username)}")
      end

      def skip_unless_postgres_available!
        return if AcceptanceSupport::DockerCompose.reachable?

        skip "Postgres not reachable at #{POSTGRES_HOST}:#{POSTGRES_PORT} and Docker is not available."
      end
    end
  end
end
