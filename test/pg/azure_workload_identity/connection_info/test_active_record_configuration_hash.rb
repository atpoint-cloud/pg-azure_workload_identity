# frozen_string_literal: true

require "test_helper"

module PG
  module AzureWorkloadIdentity
    module ConnectionInfo
      class TestActiveRecordConfigurationHash < Minitest::Test
        # Shape produced by ActiveRecord from a database.yml entry such as:
        #
        #   production:
        #     adapter: postgresql
        #     host: mydb.postgres.database.azure.com
        #     port: 5432
        #     database: appdb
        #     username: myuser@mytenant.onmicrosoft.com
        #     sslmode: require
        #     azure_workload_identity: true
        EXAMPLE_CONFIG = {
          adapter: "postgresql",
          host: "mydb.postgres.database.azure.com",
          port: 5432,
          database: "appdb",
          username: "myuser@mytenant.onmicrosoft.com",
          sslmode: "require",
          azure_workload_identity: true
        }.freeze

        def test_exposes_host_and_port_from_the_configuration_hash
          config = ActiveRecordConfigurationHash.new(EXAMPLE_CONFIG)

          assert_equal "mydb.postgres.database.azure.com", config.host
          assert_equal 5432,                               config.port
        end

        def test_maps_active_record_username_key_to_user
          config = ActiveRecordConfigurationHash.new(EXAMPLE_CONFIG)

          assert_equal "myuser@mytenant.onmicrosoft.com", config.user
        end

        def test_exposes_azure_workload_identity_flag_from_the_configuration_hash
          config = ActiveRecordConfigurationHash.new(EXAMPLE_CONFIG)

          assert config.azure_workload_identity
        end

        def test_azure_workload_identity_is_nil_when_the_key_is_absent
          config = ActiveRecordConfigurationHash.new(adapter: "postgresql", host: "localhost")

          assert_nil config.azure_workload_identity
        end

        def test_accessors_return_nil_for_missing_keys
          config = ActiveRecordConfigurationHash.new({})

          assert_nil config.host
          assert_nil config.port
          assert_nil config.user
          assert_nil config.azure_workload_identity
        end
      end
    end
  end
end
