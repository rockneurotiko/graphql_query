defmodule GraphqlQueryTest do
  use ExUnit.Case
  import GraphqlQuery
  doctest GraphqlQuery

  describe "validate/1" do
    test "uses default document name on errors" do
      # Test that the default document name is used in error messages
      assert {:error, [error]} = GraphqlQuery.validate("query T() { field }")
      assert error =~ "expected a Variable Definition"
      assert error =~ "document.graphql:1:9"
    end

    test "uses specified document name on errors" do
      # Test that the default document name is used in error messages
      assert {:error, [error]} = GraphqlQuery.validate("query T() { field }", "test.graphql")
      assert error =~ "expected a Variable Definition"
      assert error =~ "test.graphql:1:9"
    end

    test "validates correct GraphQL queries" do
      assert GraphqlQuery.validate("query TestQuery($a: String!) { user(id: $a) { id name } }") ==
               :ok
    end

    test "validates GraphQL queries with syntax errors" do
      result = GraphqlQuery.validate("query T { field\n? }")
      assert {:error, [error]} = result
      assert error =~ "Error: syntax error: Unexpected character \"?\""
    end

    test "validates GraphQL queries with unused variables" do
      # Query with unused variable should return validation error
      result = GraphqlQuery.validate("query T($a: String) { field }")
      assert {:error, [error]} = result
      assert error =~ "Error: unused variable: `$a`"
      assert error =~ "variable is never used"
    end
  end

  describe "format/1" do
    test "formats GraphQL queries" do
      non_formatted = """
      query GetUser($id: ID!) { user(id: $id) {
          id
          name
          email
          posts { title content
          } } }
      """

      formatted_query = """
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

      assert formatted_query == GraphqlQuery.format(non_formatted)

      # Test with invalid query - should return original
      invalid_query = "query T{"
      assert GraphqlQuery.format(invalid_query) == invalid_query
    end
  end

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
      assert logs =~ "GraphQL validation errors"
      assert logs =~ "Error: syntax error: expected at least one Selection in Selection Set"
    end
  end
end
