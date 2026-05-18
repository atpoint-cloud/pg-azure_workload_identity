# frozen_string_literal: true

require "test_helper"

module PG
  module AzureWorkloadIdentity
    module ConnectionInfo
      class TestKeyValueString < Minitest::Test
        EXAMPLE_CONNSTR = "host=mydb.postgres.database.azure.com " \
                          "user=myuser@mytenant.onmicrosoft.com " \
                          "dbname=appdb sslmode=require " \
                          "azure_workload_identity=true"

        def test_parses_a_typical_local_connection_string
          conn = KeyValueString.new("host=localhost port=5432 user=admin dbname=mydb")

          assert_equal "localhost", conn.host
          assert_equal "5432",      conn.port
          assert_equal "admin",     conn.user
        end

        def test_parses_a_real_world_azure_connection_string
          conn = KeyValueString.new(EXAMPLE_CONNSTR)

          assert_equal "mydb.postgres.database.azure.com",   conn.host
          assert_equal "myuser@mytenant.onmicrosoft.com",    conn.user
          assert_equal "true",                               conn.azure_workload_identity
        end

        def test_azure_workload_identity_is_nil_when_absent
          conn = KeyValueString.new("host=localhost user=admin")

          assert_nil conn.azure_workload_identity
        end

        def test_to_h_excludes_the_extracted_azure_workload_identity
          conn = KeyValueString.new(EXAMPLE_CONNSTR)

          refute_includes conn.to_h.keys, :azure_workload_identity
          assert_equal "require", conn.to_h[:sslmode]
        end

        def test_supports_single_quoted_values_with_whitespace
          conn = KeyValueString.new("host=localhost password='s3cr3t pass'")

          assert_equal "s3cr3t pass", conn.to_h[:password]
        end

        def test_unescapes_backslash_sequences_in_quoted_values
          # password = it's secret
          conn = KeyValueString.new("password='it\\'s secret'")

          assert_equal "it's secret", conn.to_h[:password]
        end

        def test_unescapes_backslash_sequences_in_unquoted_values
          # password = value with spaces
          conn = KeyValueString.new('password=value\\ with\\ spaces')

          assert_equal "value with spaces", conn.to_h[:password]
        end

        def test_tolerates_whitespace_around_the_equals_sign
          conn = KeyValueString.new("host = localhost   port=5432")

          assert_equal "localhost", conn.host
          assert_equal "5432",      conn.port
        end

        def test_password_setter_adds_the_parameter
          conn = KeyValueString.new("host=localhost user=admin")
          conn.password = "secret"

          assert_equal "secret", conn.to_h[:password]
        end

        def test_to_s_round_trips_through_the_parser
          reparsed = KeyValueString.new(KeyValueString.new(EXAMPLE_CONNSTR).to_s)

          assert_equal "mydb.postgres.database.azure.com",  reparsed.host
          assert_equal "myuser@mytenant.onmicrosoft.com",   reparsed.user
          assert_equal "require",                           reparsed.to_h[:sslmode]
          # azure_workload_identity is extracted at construction and not re-emitted
          assert_nil reparsed.azure_workload_identity
        end

        def test_raises_when_a_keyword_is_not_followed_by_equals
          assert_raises(Error) { KeyValueString.new("host localhost") }
        end

        def test_raises_when_a_quoted_value_is_not_terminated
          assert_raises(Error) { KeyValueString.new("password='oops") }
        end
      end
    end
  end
end
