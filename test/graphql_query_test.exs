defmodule GraphqlQueryTest do
  use ExUnit.Case
  import GraphqlQuery
  doctest GraphqlQuery

  describe "~GQL sigil" do
    test "returns the same query string when valid" do
      original_query = """
      query GetUser($id: ID!) {
        user(id: $id) {
          id
          name
          email
          posts {
            title
            content
          }
        }
      }
      """

      sigil_query = ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          id
          name
          email
          posts {
            title
            content
          }
        }
      }
      """

      assert sigil_query == original_query
    end

    test "works with simple valid queries" do
      query = """
      {
        user {
          id
          name
        }
      }
      """

      sigil_query = ~GQL"""
      {
        user {
          id
          name
        }
      }
      """

      assert sigil_query == query
    end
  end

  describe "gql macro" do
    test "works with static queries" do
      query =
        gql """
        query GetUser($id: ID!) {
          user(id: $id) {
            name
            email
          }
        }
        """

      expected = """
      query GetUser($id: ID!) {
        user(id: $id) {
          name
          email
        }
      }
      """

      assert query == expected
    end

    test "shows warning for static queries recommending ~GQL sigil" do
      module = """
      defmodule TestGqlStatic do
        import GraphqlQuery

        def static_query do
          gql "query { user { name } }"
        end
      end
      """

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_string(module)
        end)

      assert logs =~ "warning"
      assert logs =~ "[GraphqlQuery] GraphQL query is static"
      assert logs =~ "Using the ~GQL sigil for static queries is recommended"
    end

    test "works with module attributes" do
      defmodule TestGqlAttributes do
        import GraphqlQuery

        @fields "id name email"

        def query_with_attributes do
          gql """
          query GetUser($id: ID!) {
            user(id: $id) {
              #{@fields}
            }
          }
          """
        end
      end

      result = TestGqlAttributes.query_with_attributes()
      assert result =~ "query GetUser($id: ID!)"
      assert result =~ "id name email"
    end

    test "works with other GQL results in module attributes" do
      defmodule TestGqlWithFragments do
        import GraphqlQuery

        @user_fragment ~GQL"""
        fragment UserFields on User {
          name
          email
        }
        """i

        def query_with_fragment do
          gql """
          query {
            user {
              ...UserFields
            }
          }
          #{@user_fragment}
          """
        end
      end

      result = TestGqlWithFragments.query_with_fragment()
      assert result =~ "query {"
      assert result =~ "...UserFields"
      assert result =~ "fragment UserFields on User"
    end

    test "works with evaluate option and module calls" do
      defmodule TestGqlEvaluate do
        import GraphqlQuery

        defmodule Helper do
          def fragment_name, do: "UserIdentifier"

          def fragment do
            ~GQL"""
            fragment UserIdentifier on User {
              id
              email
            }
            """i
          end

          def more_fields, do: ["name", "surname"] |> Enum.join("\n")
        end

        def query_with_evaluate do
          gql [evaluate: true], """
          query T {
            ...#{Helper.fragment_name()}
            #{Helper.more_fields()}
          }

          #{Helper.fragment()}
          """
        end
      end

      result = TestGqlEvaluate.query_with_evaluate()
      assert result =~ "...UserIdentifier"
      assert result =~ "name\nsurname"
      assert result =~ "fragment UserIdentifier on User"
    end

    test "shows warning for local variables that cannot be expanded" do
      # Test with runtime option since local variables can't be expanded at compile time
      defmodule TestGqlLocalVars do
        import GraphqlQuery

        def query_with_local_vars do
          fields = ["id", "name", "email"]

          # This should work at runtime
          gql [runtime: true], """
          query GetUser($id: ID!) {
            user(id: $id) {
              #{Enum.join(fields, "\n")}
            }
          }
          """
        end
      end

      # This should compile without issues and work at runtime
      result = TestGqlLocalVars.query_with_local_vars()
      assert result =~ "query GetUser($id: ID!)"
      assert result =~ "id\nname\nemail"
    end

    test "string directly in replace" do
      gql [evaluate: true], """
      query Test {
        user {
          #{"name"}
        }
      }
      """
    end

    test "shows warning when expansion fails without evaluate" do
      module = """
      defmodule TestGqlExpansionWarning do
        import GraphqlQuery

        defmodule Helper do
          def some_field, do: "name"
        end

        def query_with_failed_expansion do
          gql "query { \#{Helper.some_field()} }"
        end
      end
      """

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_string(module)
        end)

      assert logs =~ "warning"
      assert logs =~ "[GraphqlQuery] Could not expand the part"
      assert logs =~ "To try to evaluate calls at compile time, use the `evaluate: true` option"
    end

    test "works with runtime validation option" do
      defmodule TestGqlRuntime do
        import GraphqlQuery

        def query_with_runtime_validation(user_id) do
          fields = ["id", "name", "email"]

          gql [runtime: true], """
          query GetUser($id: ID!) {
            user(id: #{user_id}) {
              #{Enum.join(fields, "\n")}
            }
          }
          """
        end
      end

      # The query should work and return the interpolated string
      result = TestGqlRuntime.query_with_runtime_validation("$id")
      assert result =~ "query GetUser($id: ID!)"
      assert result =~ "user(id: $id)"
      assert result =~ "id\nname\nemail"
    end

    test "works with ignore option" do
      defmodule TestGqlIgnore do
        import GraphqlQuery

        def query_with_ignore_option do
          fields = ["id", "name"]

          gql [ignore: true], """
          query {
            user {
              #{Enum.join(fields, "\n")}
            }
          }
          """
        end
      end

      # Should work without any warnings or validation
      result = TestGqlIgnore.query_with_ignore_option()
      assert result =~ "query {"
      assert result =~ "id\nname"
    end

    test "ignore option suppresses warnings" do
      module = """
      defmodule TestGqlIgnoreWarnings do
        import GraphqlQuery

        defmodule Helper do
          def some_field, do: "name"
        end

        def query_with_ignore do
          gql [ignore: true], "query { \#{Helper.some_field()} }"
        end
      end
      """

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_string(module)
        end)

      # Should not contain any GraphqlQuery warnings
      refute logs =~ "[GraphqlQuery]"
    end

    test "works with module-level options using 'use' statement" do
      defmodule TestGqlModuleOptions do
        use GraphqlQuery, evaluate: true, runtime: true

        defmodule Helper do
          def get_fields, do: "id name"
        end

        def query_with_module_options do
          # Should try to evaluate first, then fall back to runtime if needed
          gql """
          query {
            user {
              #{Helper.get_fields()}
            }
          }
          """
        end
      end

      result = TestGqlModuleOptions.query_with_module_options()
      assert result =~ "query {"
      assert result =~ "id name"
    end

    test "validates and warns about invalid GraphQL in gql macro" do
      module = """
      defmodule TestGqlValidation do
        import GraphqlQuery

        @fields "id name"

        def invalid_query do
          gql \"""
          query GetUser($unused: String) {
            user {
              \#{@fields}
            }
          }
          \"""
        end
      end
      """

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_string(module)
        end)

      assert logs =~ "warning"
      assert logs =~ "unused variable"
    end
  end

  describe "compile warnings" do
    test "compile warning" do
      module = """
      defmodule TestSigilWarning do
        import GraphqlQuery

        def wrong_query do
          ~GQL"{}"
        end
      end
      """

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_string(module)
        end)

      assert logs =~ "warning"
      assert logs =~ "Validation errors"
      assert logs =~ "Error: syntax error: expected at least one Selection in Selection Set"
    end
  end
end
