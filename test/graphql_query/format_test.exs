defmodule GraphqlQuery.FormatTest do
  use ExUnit.Case

  alias GraphqlQuery.Format

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

      assert formatted_query == Format.format(non_formatted)

      # Test with invalid query - should return original
      invalid_query = "query T{"
      assert Format.format(invalid_query) == invalid_query
    end
  end
end
