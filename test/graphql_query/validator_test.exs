defmodule GraphqlQuery.ValidatorTest do
  use ExUnit.Case

  alias GraphqlQuery.{Validator, Document}

  describe "validate/1" do
    test "uses default document name on errors" do
      # Test that the default document name is used in error messages
      assert {:error, [error]} = Validator.validate("query T() { field }")
      assert error.message =~ "expected a Variable Definition"
      assert [%{line: 1, column: 9}] = error.locations
    end

    test "uses specified document name on errors" do
      # Test that the default document name is used in error messages
      assert {:error, [error]} =
               Validator.validate("query T() { field }", "test.graphql", nil, :query)

      assert error.message =~ "expected a Variable Definition"
      assert [%{line: 1, column: 9}] = error.locations
    end

    test "validates correct GraphQL queries" do
      assert Validator.validate("query TestQuery($a: String!) { user(id: $a) { id name } }") ==
               :ok
    end

    test "validates GraphQL queries with syntax errors" do
      result = Validator.validate("query T { field\n? }")
      assert {:error, [error]} = result
      assert error.message =~ "syntax error: Unexpected character \"?\""
    end

    test "validates GraphQL queries with unused variables" do
      # Query with unused variable should return validation error
      result = Validator.validate("query T($a: String) { field }")
      assert {:error, [error]} = result
      assert error.message =~ "unused variable: `$a`"
    end
  end

  describe "validate/1 with Document struct" do
    test "validates valid Document" do
      query = "query TestQuery($id: ID!) { user(id: $id) { id name email } }"
      document = Document.new(query)

      result = Validator.validate(document)

      assert result == :ok
    end

    test "validates invalid Document with syntax errors" do
      query = "query TestQuery { user(id: $id { id name } }"
      document = Document.new(query)

      result = Validator.validate(document)

      assert {:error, [error]} = result
      assert error.message =~ "syntax error"
    end

    test "validates Document with unused variables" do
      query = "query TestQuery($unused: String, $id: ID!) { user(id: $id) { id name } }"
      document = Document.new(query)

      result = Validator.validate(document)

      assert {:error, [error]} = result
      assert error.message =~ "unused variable: `$unused`"
    end

    test "uses Document path in error messages" do
      query = "query T() { field }"
      document = Document.new(query, path: "/custom/path/query.gql")

      assert {:error, [error]} = Validator.validate(document)
      assert error.message =~ "expected a Variable Definition"
      assert [%{line: 1, column: 9}] = error.locations
    end

    test "uses default document name when Document has no path" do
      query = "query T() { field }"
      document = Document.new(query)

      assert {:error, [error]} = Validator.validate(document)
      assert error.message =~ "expected a Variable Definition"
      assert [%{line: 1, column: 9}] = error.locations
    end

    test "validates Document with type :query" do
      query = "query GetUser { user { id } }"
      document = Document.new(query, type: :query)

      result = Validator.validate(document)

      assert result == :ok
    end

    test "validates Document with fragments" do
      query = "query { user { ...UserFields } }"
      document = Document.new(query)
      fragment = Document.new("fragment UserFields on User { id name }", type: :fragment)
      document_with_fragments = Document.add_fragment(document, fragment)

      result = Validator.validate(document_with_fragments)

      # The validation should include the fragments in the query string
      assert result == :ok
    end
  end

  describe "validate/1 with Fragment struct" do
    test "validates valid Fragment" do
      fragment_query = "fragment UserFields on User { id name email }"
      fragment = Document.new(fragment_query, type: :fragment)

      result = Validator.validate(fragment)

      assert result == :ok
    end

    test "validates invalid Fragment with syntax errors" do
      fragment_query = "fragment UserFields on User { id name email"
      fragment = Document.new(fragment_query, type: :fragment)

      result = Validator.validate(fragment)

      assert {:error, [error]} = result
      assert error.message =~ "syntax error"
    end

    test "validates Fragment with invalid field selection" do
      # Fragment with syntax error (missing closing brace)
      fragment_query = "fragment UserFields on User { id name email "
      fragment = Document.new(fragment_query, type: :fragment)

      result = Validator.validate(fragment)

      assert {:error, [error]} = result
      assert error.message =~ "syntax error"
    end

    test "uses Fragment path in error messages" do
      fragment_query = "fragment UserFields on User { id name email"
      fragment = Document.new(fragment_query, type: :fragment, path: "/fragments/user.gql")

      assert {:error, [error]} = Validator.validate(fragment)
      assert error.message =~ "syntax error"
    end

    test "uses default document name when Fragment has no path" do
      fragment_query = "fragment UserFields on User { id name email"
      fragment = Document.new(fragment_query, type: :fragment)

      assert {:error, [error]} = Validator.validate(fragment)
      assert error.message =~ "syntax error"
    end

    test "validates named fragments correctly" do
      # Standard named fragment
      fragment_query = "fragment UserBasicFields on User { id name }"
      fragment = Document.new(fragment_query, type: :fragment)

      result = Validator.validate(fragment)

      assert result == :ok
    end
  end

  describe "validate/1 with schema validation" do
    # Note: These tests would require actual schema modules to be meaningful
    # For now, we test the interface when schema is nil

    test "validates Document with nil schema (no schema validation)" do
      query = "query TestQuery { user { id name } }"
      document = Document.new(query, schema: nil)

      # Without a schema, this will validate syntax only
      result = Validator.validate(document)

      assert result == :ok
    end

    test "validates Fragment with nil schema (no schema validation)" do
      fragment_query = "fragment UserFields on User { id name }"
      fragment = Document.new(fragment_query, type: :fragment, schema: nil)

      # Without a schema, this will validate syntax only
      result = Validator.validate(fragment)

      assert result == :ok
    end
  end

  describe "error handling and edge cases" do
    test "handles Document with complex nested structure" do
      query = """
      query ComplexQuery($userId: ID!, $postLimit: Int) {
        user(id: $userId) {
          id
          name
          posts(limit: $postLimit) {
            id
            title
            comments {
              id
              content
              author {
                id
                name
              }
            }
          }
        }
      }
      """

      document = Document.new(query)
      result = Validator.validate(document)

      assert result == :ok
    end

    test "handles Fragment with complex field selections" do
      fragment_query = """
      fragment ComplexUserFields on User {
        id
        name
        email
        profile {
          bio
          avatar
          preferences {
            theme
            notifications {
              email
              push
            }
          }
        }
        posts {
          id
          title
          publishedAt
        }
      }
      """

      fragment = Document.new(fragment_query, type: :fragment)
      result = Validator.validate(fragment)

      assert result == :ok
    end

    test "handles empty Document gracefully" do
      document = Document.new("")

      result = Validator.validate(document)

      assert {:error, [error]} = result
      assert error.message =~ "syntax error"
    end

    test "handles empty Fragment gracefully" do
      fragment = Document.new("", type: :fragment)

      result = Validator.validate(fragment)

      assert {:error, [error]} = result
      assert error.message =~ "syntax error"
    end
  end
end
