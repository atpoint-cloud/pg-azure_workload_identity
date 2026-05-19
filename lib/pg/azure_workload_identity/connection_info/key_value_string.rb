# frozen_string_literal: true

require "strscan"
require "pg"

require_relative "../error"

module PG
  module AzureWorkloadIdentity
    module ConnectionInfo
      # Parses and manipulates a PostgreSQL connection string in libpq's
      # key=value format (e.g. `"host=localhost user=admin port=5432"`).
      #
      # The parser preserves functional parity with libpq's `conninfo_parse`,
      # supporting whitespace around the `=`, single-quoted values, and
      # backslash escapes (`\\X` -> `X`) in both quoted and unquoted values.
      #
      # The non-standard `azure_workload_identity` parameter is recognized and
      # extracted on construction so it can drive Azure Workload Identity
      # authentication without being forwarded to libpq.
      #
      # @see https://github.com/postgres/postgres/blob/REL_18_4/src/interfaces/libpq/fe-connect.c#L6289-L6444
      class KeyValueString
        # @return [String, nil] the value of the `azure_workload_identity`
        #   parameter that was present in the original connection string, or
        #   `nil` if the parameter was not set.
        attr_reader :azure_workload_identity

        # Parses the given connection string and extracts the
        # `azure_workload_identity` parameter (if any) so it is not forwarded to
        # libpq.
        #
        # @param connection_string [String] a PostgreSQL key=value connection
        #   string.
        # @raise [Error] if the connection string is malformed.
        def initialize(connection_string)
          @params = Parser.new(connection_string).parse
          @azure_workload_identity = @params.delete(:azure_workload_identity)
        end

        # @return [String, nil] the value of the `user` parameter.
        def user
          @params[:user]
        end

        # @return [String, nil] the value of the `host` parameter.
        def host
          @params[:host]
        end

        # @return [String, nil] the value of the `port` parameter.
        def port
          @params[:port]
        end

        # Sets the `password` parameter.
        #
        # @param value [String] the password to set.
        # @return [String] the value that was set.
        def password=(value)
          @params[:password] = value
        end

        # Serializes the parameters back to a libpq key=value connection
        # string. Values are quoted/escaped via `PG::Connection.quote_connstr`
        # so they remain valid when whitespace or special characters are
        # present. The `azure_workload_identity` parameter extracted at
        # construction is not included.
        #
        # @return [String] the connection string.
        def to_s
          @params.map { |key, value| "#{key}=#{PG::Connection.quote_connstr(value)}" }.join(" ")
        end

        # @return [Hash{Symbol => String}] a copy of the parsed parameters
        #   (excluding `azure_workload_identity`, which was extracted at
        #   construction).
        def to_h
          @params.dup
        end

        # Tokenizes a libpq key=value connection string into a hash of
        # symbol-keyed parameters.
        #
        # The grammar mirrors `conninfo_parse`: whitespace separates pairs,
        # whitespace is allowed around `=`, values may be single-quoted, and
        # `\\X` unescapes to `X` in both quoted and unquoted values. A
        # trailing backslash at EOF inside an unquoted value is silently
        # dropped (matching libpq).
        #
        # @see https://github.com/postgres/postgres/blob/REL_18_4/src/interfaces/libpq/fe-connect.c#L6289-L6444
        class Parser
          # @param connection_string [String] the connection string to parse.
          def initialize(connection_string)
            @buffer = StringScanner.new(connection_string)
          end

          # Parses the connection string passed to the constructor.
          #
          # @return [Hash{Symbol => String}] the parsed parameters, in the
          #   order they appeared in the input. Later occurrences of the same
          #   key overwrite earlier ones.
          # @raise [Error] when a keyword is missing, `=` is missing
          #   after a keyword, or a quoted value is not terminated.
          def parse # rubocop:disable Metrics/MethodLength
            result = {} # : Hash[Symbol, String]

            skip_whitespace
            until @buffer.eos?
              key = parse_key
              skip_whitespace
              assert_followed_by_equals_sign key
              skip_whitespace
              value = parse_value
              skip_whitespace

              result[key] = value
            end

            @buffer.reset
            result
          end

          private

          # Advances the scanner past any run of whitespace characters.
          #
          # @return [Integer, nil] the number of characters consumed, or
          #   `nil` if none matched.
          def skip_whitespace
            @buffer.skip(/\s+/)
          end

          # Reads the next keyword (any run of non-whitespace, non-`=`
          # characters) and returns it as a symbol.
          #
          # @return [Symbol] the keyword.
          # @raise [Error] if no keyword characters are present at the
          #   current position.
          def parse_key
            key = @buffer.scan(/[^=\s]+/)
            raise Error, %(Missing parameter name before "#{@buffer.rest}") unless key

            key.to_sym
          end

          # Consumes a single `=` character at the current position.
          #
          # @param key [Symbol] the keyword that should be followed by `=`
          #   (used in the error message).
          # @raise [Error] if the next character is not `=`.
          # @return [void]
          def assert_followed_by_equals_sign(key)
            raise Error, %(Missing "=" after "#{key}") unless @buffer.getch == "="
          end

          # Reads a value, dispatching to the quoted or unquoted form based
          # on whether the next character is a single quote.
          #
          # @return [String] the parsed value (may be empty).
          # @raise [Error] if a quoted value is not terminated.
          def parse_value
            if @buffer.peek(1) == "'"
              parse_quoted_value
            else
              parse_unquoted_value
            end
          end

          # Reads a single-quoted value, applying `\\X` -> `X` escape
          # handling.
          #
          # @return [String] the value with quotes stripped and escapes
          #   applied.
          # @raise [Error] if the closing quote is missing.
          def parse_quoted_value
            value = +""
            @buffer.skip(/'/)
            loop do
              value << (@buffer.scan(/[^'\\]+/) || "")
              case @buffer.getch
              when "'" then return value
              when "\\" then value << (@buffer.getch || "")
              else raise Error, "Unterminated quoted value"
              end
            end
          end

          # Reads an unquoted value, terminating at the next whitespace and
          # applying `\\X` -> `X` escape handling. A trailing backslash at
          # EOF is silently dropped (matching libpq).
          #
          # @return [String] the value with escapes applied (may be empty).
          def parse_unquoted_value
            value = +""
            loop do
              value << (@buffer.scan(/[^\s\\]+/) || "")
              return value unless @buffer.getch == "\\"

              value << (@buffer.getch || "")
            end
          end
        end
      end
    end
  end
end
