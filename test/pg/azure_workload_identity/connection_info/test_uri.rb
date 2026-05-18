# frozen_string_literal: true

require "test_helper"

module PG
  module AzureWorkloadIdentity
    module ConnectionInfo
      class TestURI < Minitest::Test
        def test_match_distinguishes_uri_format_from_key_value_format
          assert URI.matches?("postgres://localhost/db")
          assert URI.matches?("postgresql://user:pass@host:5432/db?sslmode=require")
          refute URI.matches?("host=localhost user=admin")
          refute URI.matches?("")
        end

        def test_exposes_components_from_the_uri
          uri = URI.new("postgres://admin:secret@db.example.com:5433/app")

          assert_equal "admin", uri.user
          assert_equal "db.example.com", uri.host
          assert_equal 5433, uri.port
        end

        def test_falls_back_to_query_parameters_when_uri_components_are_missing
          uri = URI.new("postgres:///app?user=admin&host=db.example.com&port=5433")

          assert_equal "admin", uri.user
          assert_equal "db.example.com", uri.host
          assert_equal "5433", uri.port
        end

        def test_extracts_azure_workload_identity_from_the_query_string
          uri = URI.new("postgres://host/db?azure_workload_identity=true&sslmode=require")

          assert_equal "true", uri.azure_workload_identity
        end

        def test_azure_workload_identity_is_nil_when_the_parameter_is_absent
          assert_nil URI.new("postgres://host/db").azure_workload_identity
        end

        def test_password_setter_replaces_userinfo_password_with_a_query_parameter
          uri = URI.new("postgres://admin:old@host/db")
          uri.password = "new-secret"

          serialized = uri.to_s

          refute_includes serialized, "old"
          assert_includes serialized, "password=new-secret"
        end

        def test_to_s_omits_the_extracted_azure_workload_identity_parameter
          uri = URI.new("postgres://host/db?azure_workload_identity=true&sslmode=require")

          serialized = uri.to_s

          refute_includes serialized, "azure_workload_identity"
          assert_includes serialized, "sslmode=require"
        end

        def test_to_s_round_trips_through_the_parser
          original = "postgres://admin@db.example.com:5432/app?sslmode=require"
          reparsed = URI.new(URI.new(original).to_s)

          assert_equal "admin", reparsed.user
          assert_equal "db.example.com", reparsed.host
          assert_equal 5432, reparsed.port
        end
      end
    end
  end
end
