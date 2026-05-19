# frozen_string_literal: true

require_relative "acceptance_test"

module PG
  module AzureWorkloadIdentity
    # Acceptance tests covering direct PG.connect usage.
    class TestPG < AcceptanceTest
      def test_pg_connect_with_azure_workload_identity
        conn = PG.connect(
          host: POSTGRES_HOST,
          port: POSTGRES_PORT,
          dbname: POSTGRES_DB,
          user: @username,
          azure_workload_identity: "true"
        )

        result = conn.exec("SELECT TRUE AS success")

        assert result.first["success"]
        assert_requested :post, AAD_TOKEN_URL, times: 1
      ensure
        conn&.close
      end

      def test_pg_connect_without_azure_workload_identity
        conn = PG.connect(
          host: POSTGRES_HOST,
          port: POSTGRES_PORT,
          dbname: POSTGRES_DB,
          user: @username,
          password: @access_token
        )

        result = conn.exec("SELECT TRUE AS success")

        assert result.first["success"]
        assert_not_requested :post, AAD_TOKEN_URL
      ensure
        conn&.close
      end
    end
  end
end
