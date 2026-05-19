# frozen_string_literal: true

require "test_helper"

module PG
  module AzureWorkloadIdentity
    class TestConnectionInfo < Minitest::Test
      def test_from_connection_string_returns_a_uri_wrapper_for_uri_format_input
        info = ConnectionInfo.from_connection_string("postgres://admin@db.example.com:5432/app")

        assert_kind_of ConnectionInfo::URI, info
        assert_equal "admin",            info.user
        assert_equal "db.example.com",   info.host
        assert_equal 5432,               info.port
      end

      def test_from_connection_string_returns_a_key_value_wrapper_for_key_value_input
        info = ConnectionInfo.from_connection_string("host=db.example.com user=admin port=5432")

        assert_kind_of ConnectionInfo::KeyValueString, info
        assert_equal "admin",            info.user
        assert_equal "db.example.com",   info.host
        assert_equal "5432",             info.port
      end

      def test_from_active_record_configuration_hash_returns_a_configuration_hash_wrapper
        info = ConnectionInfo.from_active_record_configuration_hash(
          host: "db.example.com",
          port: 5432,
          username: "admin",
          azure_workload_identity: true
        )

        assert_kind_of ConnectionInfo::ActiveRecordConfigurationHash, info
        assert_equal "admin",            info.user
        assert_equal "db.example.com",   info.host
        assert_equal 5432,               info.port
        assert info.azure_workload_identity
      end
    end
  end
end
