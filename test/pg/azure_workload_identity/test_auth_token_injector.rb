# frozen_string_literal: true

require "test_helper"

module PG
  module AzureWorkloadIdentity
    class TestAuthTokenInjector < Minitest::Test
      TOKEN = "fresh.access.token"

      # A generator that fails the test if invoked — used to assert the
      # injector doesn't fetch a token when it has no reason to.
      def raising_generator
        -> { raise "auth_token_generator should not have been called" }
      end

      def static_generator(token = TOKEN)
        -> { token }
      end

      # --- inject_into_connection_string ------------------------------------

      def test_injects_password_into_a_key_value_connection_string_when_the_flag_is_set
        injector = AuthTokenInjector.new(auth_token_generator: static_generator)

        result = injector.inject_into_connection_string(
          "host=localhost user=app azure_workload_identity=true"
        )

        assert_includes result, "password='#{TOKEN}'"
        refute_includes result, "azure_workload_identity"
      end

      def test_injects_password_into_a_uri_connection_string_when_the_flag_is_set
        injector = AuthTokenInjector.new(auth_token_generator: static_generator)

        result = injector.inject_into_connection_string(
          "postgres://app@localhost/db?azure_workload_identity=true"
        )

        assert_includes result, "password=#{TOKEN}"
        refute_includes result, "azure_workload_identity"
      end

      def test_returns_the_connection_string_unchanged_when_the_flag_is_absent
        injector = AuthTokenInjector.new(auth_token_generator: raising_generator)

        connstr = "host=localhost user=app"

        assert_equal connstr, injector.inject_into_connection_string(connstr)
      end

      # --- inject_into_psql_env! --------------------------------------------

      def test_inject_into_psql_env_sets_pgpassword_when_the_flag_is_truthy
        injector = AuthTokenInjector.new(auth_token_generator: static_generator)
        env = {}

        injector.inject_into_psql_env!({ host: "localhost", azure_workload_identity: true }, env)

        assert_equal TOKEN, env["PGPASSWORD"]
      end

      def test_inject_into_psql_env_leaves_env_untouched_when_the_flag_is_absent
        injector = AuthTokenInjector.new(auth_token_generator: raising_generator)
        env = {}

        injector.inject_into_psql_env!({ host: "localhost" }, env)

        assert_empty env
      end
    end
  end
end
