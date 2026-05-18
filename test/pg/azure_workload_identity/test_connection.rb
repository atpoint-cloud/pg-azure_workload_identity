# frozen_string_literal: true

require "test_helper"

module PG
  module AzureWorkloadIdentity
    # Exercises the monkey-patch prepended to PG::Connection.singleton_class.
    # These tests don't open a database connection — every method under test
    # is a pure transformation that can run against the loaded pg gem.
    class TestConnection < Minitest::Test
      TOKEN = "fresh.access.token"

      def setup
        super
        # Capture the module-level generator without triggering lazy init.
        @original_generator = AzureWorkloadIdentity.instance_variable_get(:@auth_token_generator)
      end

      def teardown
        # Restore (possibly to nil), so we don't leak a stub into other tests.
        AzureWorkloadIdentity.instance_variable_set(:@auth_token_generator, @original_generator)
        super
      end

      # --- conndefaults -----------------------------------------------------

      def test_conndefaults_includes_the_azure_workload_identity_entry
        entry = PG::Connection.conndefaults.find { |e| e[:keyword] == "azure_workload_identity" }

        refute_nil entry, "expected conndefaults to advertise azure_workload_identity"
        assert_equal "Azure-Workload-Identity", entry[:label]
      end

      # --- conninfo_parse ---------------------------------------------------

      def test_conninfo_parse_preserves_azure_workload_identity_when_set
        result = PG::Connection.conninfo_parse(
          "host=localhost azure_workload_identity=true"
        )

        entry = result.find { |e| e[:keyword] == "azure_workload_identity" }

        refute_nil entry, "expected azure_workload_identity to be preserved in the parsed result"
        assert_equal "true", entry[:val]
      end

      def test_conninfo_parse_does_not_emit_azure_workload_identity_when_absent
        result = PG::Connection.conninfo_parse("host=localhost")

        entry = result.find { |e| e[:keyword] == "azure_workload_identity" }

        assert_nil entry, "azure_workload_identity entry should be absent when not in the input"
      end

      # --- parse_connect_args ----------------------------------------------

      def test_parse_connect_args_injects_password_when_azure_workload_identity_is_set
        AzureWorkloadIdentity.auth_token_generator = -> { TOKEN }

        result = PG::Connection.send(
          :parse_connect_args,
          "host=localhost user=app azure_workload_identity=true"
        )

        assert_includes result, "password='#{TOKEN}'"
        refute_includes result, "azure_workload_identity"
      end

      def test_parse_connect_args_returns_unchanged_when_flag_is_absent
        AzureWorkloadIdentity.auth_token_generator = lambda {
          raise "auth_token_generator should not have been called"
        }

        result = PG::Connection.send(:parse_connect_args, "host=localhost user=app")

        refute_includes result, "password"
      end
    end
  end
end
