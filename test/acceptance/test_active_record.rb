# frozen_string_literal: true

require_relative "acceptance_test"

module PG
  module AzureWorkloadIdentity
    # Acceptance tests covering ActiveRecord connection and schema-loading
    # flows.
    class TestActiveRecord < AcceptanceTest
      def test_active_record_base_establish_connection_with_azure_workload_identity
        ActiveRecord::Base.establish_connection(database_url(
                                                  username: @username,
                                                  azure_workload_identity: true
                                                ))

        begin
          result = ActiveRecord::Base.connection.exec_query("SELECT TRUE AS success")

          assert result.first["success"]
          assert_requested :post, AAD_TOKEN_URL, times: 1
        ensure
          ActiveRecord::Base.connection.disconnect!
        end
      end

      def test_active_record_base_establish_connection_without_azure_workload_identity
        ActiveRecord::Base.establish_connection(database_url(
                                                  username: @username,
                                                  password: @access_token
                                                ))

        begin
          result = ActiveRecord::Base.connection.exec_query("SELECT TRUE AS success")

          assert result.first["success"]
          assert_not_requested :post, AAD_TOKEN_URL
        ensure
          ActiveRecord::Base.connection.disconnect!
        end
      end

      def test_active_record_load_schema_with_azure_workload_identity
        ActiveRecord::Base.establish_connection(
          url: database_url(username: @username, azure_workload_identity: true),
          use_metadata_table: false
        )

        begin
          db_config = ActiveRecord::Base.connection_db_config

          _, stderr = capture_subprocess_io do
            ActiveRecord::Tasks::DatabaseTasks.load_schema db_config, :sql, File.expand_path("structure.sql", __dir__)
          end

          assert_includes stderr, "🚀"
          assert_requested :post, AAD_TOKEN_URL, times: 1
        ensure
          ActiveRecord::Base.connection.disconnect!
        end
      end

      def test_active_record_load_schema_without_azure_workload_identity
        ActiveRecord::Base.establish_connection(
          url: database_url(username: @username, password: @access_token),
          use_metadata_table: false
        )

        begin
          db_config = ActiveRecord::Base.connection_db_config

          _, stderr = capture_subprocess_io do
            ActiveRecord::Tasks::DatabaseTasks.load_schema db_config, :sql, File.expand_path("structure.sql", __dir__)
          end

          assert_includes stderr, "🚀"
          assert_not_requested :post, AAD_TOKEN_URL
        ensure
          ActiveRecord::Base.connection.disconnect!
        end
      end
    end
  end
end
