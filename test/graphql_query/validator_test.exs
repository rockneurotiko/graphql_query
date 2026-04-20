defmodule GraphqlQuery.ValidatorTest do
  use ExUnit.Case

  doctest GraphqlQuery.Validator

  alias GraphqlQuery.{Document, Validator}

  describe "validate/1" do
    test "uses default document name on errors" do
      # Test that the default document name is used in error messages
      assert {:error, [error]} =
               "query T() { field }" |> Document.new() |> Validator.validate()

      assert error.message =~ "expected a Variable Definition"
      assert [%{line: 1, column: 9}] = error.locations
    end

    test "uses specified document name on errors" do
      # Test that the default document name is used in error messages
      document = Document.new("query T() { field }", path: "test.graphql")
      assert {:error, [error]} = Validator.validate(document)

      assert error.message =~ "expected a Variable Definition"
      assert [%{line: 1, column: 9}] = error.locations
    end

    test "validates correct GraphQL queries" do
      query = "query TestQuery($a: String!) { user(id: $a) { id name } }"
      document = Document.new(query)
      assert :ok = Validator.validate(document)
    end

    test "validates GraphQL queries with syntax errors" do
      result = "query T { field\n? }" |> Document.new() |> Validator.validate()
      assert {:error, [error]} = result
      assert error.message =~ "syntax error: Unexpected character \"?\""
    end

    test "validates GraphQL queries with unused variables" do
      # Query with unused variable should return validation error
      result = "query T($a: String) { field }" |> Document.new() |> Validator.validate()
      assert {:error, [error]} = result
      assert error.message =~ "unused variable: `$a`"
    end
  end

  describe "validate/1 with Document struct" do
    test "validates valid Document" do
      query = "query TestQuery($id: ID!) { user(id: $id) { id name email } }"
      document = Document.new(query)

      assert :ok = Validator.validate(document)
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

      assert :ok = Validator.validate(document)
    end

    test "validates Document with fragments" do
      query = "query { user { ...UserFields } }"
      document = Document.new(query)
      fragment = Document.new("fragment UserFields on User { id name }", type: :fragment)
      document_with_fragments = Document.add_fragment(document, fragment)

      assert :ok = Validator.validate(document_with_fragments)
    end
  end

  describe "validate/1 with Fragment struct" do
    test "validates valid Fragment" do
      fragment_query = "fragment UserFields on User { id name email }"
      fragment = Document.new(fragment_query, type: :fragment)

      assert :ok = Validator.validate(fragment)
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

      assert :ok = Validator.validate(fragment)
    end
  end

  describe "validate/1 with schema validation" do
    # Note: These tests would require actual schema modules to be meaningful
    # For now, we test the interface when schema is nil

    test "validates Document with nil schema (no schema validation)" do
      query = "query TestQuery { user { id name } }"
      document = Document.new(query, schema: nil)

      # Without a schema, this will validate syntax only
      assert :ok = Validator.validate(document)
    end

    test "validates Fragment with nil schema (no schema validation)" do
      fragment_query = "fragment UserFields on User { id name }"
      fragment = Document.new(fragment_query, type: :fragment, schema: nil)

      # Without a schema, this will validate syntax only
      assert :ok = Validator.validate(fragment)
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
      assert :ok = Validator.validate(document)
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
      assert :ok = Validator.validate(fragment)
    end

    test "handles empty Document gracefully" do
      document = Document.new("")

      assert {:error, [error]} = Validator.validate(document)

      assert error.message =~ "syntax error"
    end

    test "handles empty Fragment gracefully" do
      fragment = Document.new("", type: :fragment)

      result = Validator.validate(fragment)

      assert {:error, [error]} = result
      assert error.message =~ "syntax error"
    end
  end

  describe "validate/1 — query validation with a federation schema" do
    test "accepts a valid query against a federation schema" do
      query = """
      query GetUser($id: ID!) {
        user(id: $id) {
          id
          name
          email
        }
      }
      """

      document = Document.new(query, schema: Test.FederationSchema, federation: true)
      assert :ok = Validator.validate(document)
    end

    test "rejects a query with a non-existent field against a federation schema" do
      query = """
      query GetUser {
        user(id: "1") {
          id
          ghostField
        }
      }
      """

      document = Document.new(query, schema: Test.FederationSchema, federation: true)
      assert {:error, errors} = Validator.validate(document)
      assert Enum.any?(errors, &(&1.message =~ "ghostField"))
    end

    test "accepts a query selecting multiple entity types" do
      query = """
      query GetAll {
        user(id: "1") { id name }
        product(id: "2") { id title }
      }
      """

      document = Document.new(query, schema: Test.FederationSchema, federation: true)
      assert :ok = Validator.validate(document)
    end

    test "rejects a query with a non-existent argument" do
      query = """
      query GetUser {
        user(unknownArg: "foo") {
          id
        }
      }
      """

      document = Document.new(query, schema: Test.FederationSchema, federation: true)
      assert {:error, errors} = Validator.validate(document)
      # The error must be about the unknown argument, not about unknown directives
      assert Enum.any?(errors, &(&1.message =~ ~r/unknownArg|argument/i))
      assert Enum.all?(errors, &(not (&1.message =~ "cannot find directive")))
    end

    test "federation: false on options are being overriden if the schema has federation" do
      query = """
      query GetUser($id: ID!) {
        user(id: $id) { id name }
      }
      """

      document = Document.new(query, schema: Test.FederationSchema, federation: false)
      assert :ok = Validator.validate(document)
    end

    test "ignored schema suppresses errors when federation not expanded" do
      query = """
      query GetUser($id: ID!) {
        user(id: $id) { id name }
      }
      """

      # FederationIgnoredSchema has ignore?: true, so schema errors are suppressed
      # even when federation: false is passed (unknown @link directive is ignored)
      document = Document.new(query, schema: Test.FederationIgnoredSchema, federation: false)
      assert :ok = Validator.validate(document)
    end

    test "federation option true overrides schema's one" do
      query = """
      query GetUser($id: ID!) {
        user(id: $id) { id name }
      }
      """

      document = Document.new(query, schema: Test.FederationIgnoredSchema, federation: true)

      assert :ok = Validator.validate(document)
    end

    test "schema_module.federation?/0 is used as default when not set on document" do
      # validate/5 directly (bypassing Document struct) — schema_module.federation?()
      # is the default source for federation when :federation is not in opts.
      query = "query GetUser($id: ID!) { user(id: $id) { id name } }"

      assert :ok =
               Validator.validate(query, "query.graphql", Test.FederationSchema, :query)
    end

    test "plain schema validation still works (no federation)" do
      query = """
      query GetUser($id: ID!) {
        user(id: $id) { id name }
      }
      """

      document = Document.new(query, schema: Test.Schema)
      assert :ok = Validator.validate(document)
    end
  end

  describe "validate/1 — fragment validation with a federation schema" do
    test "accepts a valid fragment against a federation schema" do
      fragment = """
      fragment UserFields on User {
        id
        name
        email
      }
      """

      document =
        Document.new(fragment, type: :fragment, schema: Test.FederationSchema, federation: true)

      assert :ok = Validator.validate(document)
    end

    test "rejects a fragment with a non-existent field against a federation schema" do
      fragment = """
      fragment UserFields on User {
        id
        ghostField
      }
      """

      document =
        Document.new(fragment, type: :fragment, schema: Test.FederationSchema, federation: true)

      assert {:error, errors} = Validator.validate(document)
      assert Enum.any?(errors, &(&1.message =~ "ghostField"))
    end

    test "accepts a fragment on a product entity" do
      fragment = """
      fragment ProductFields on Product {
        id
        title
      }
      """

      document =
        Document.new(fragment, type: :fragment, schema: Test.FederationSchema, federation: true)

      assert :ok = Validator.validate(document)
    end

    test "rejects a fragment on a non-existent type" do
      fragment = """
      fragment GhostFields on GhostType {
        id
      }
      """

      document =
        Document.new(fragment, type: :fragment, schema: Test.FederationSchema, federation: true)

      assert {:error, errors} = Validator.validate(document)
      assert Enum.any?(errors, &(&1.message =~ "GhostType"))
    end

    test "federation: false on options are being overriden if the schema has federation" do
      fragment = """
      fragment UserFields on User {
        id
        name
      }
      """

      document =
        Document.new(fragment, type: :fragment, schema: Test.FederationSchema, federation: false)

      assert :ok = Validator.validate(document)
    end

    test "ignored schema suppresses errors when federation not expanded" do
      fragment = """
      fragment UserFields on User {
        id
        name
      }
      """

      # FederationIgnoredSchema has ignore?: true, so schema errors are suppressed
      # even when federation: false is passed (unknown @link directive is ignored)
      document =
        Document.new(fragment,
          type: :fragment,
          schema: Test.FederationIgnoredSchema,
          federation: false
        )

      assert :ok = Validator.validate(document)
    end

    test "federation option true overrides schema's one" do
      fragment = """
      fragment UserFields on User {
        id
        name
      }
      """

      document =
        Document.new(fragment,
          type: :fragment,
          schema: Test.FederationIgnoredSchema,
          federation: true
        )

      assert :ok = Validator.validate(document)
    end

    test "schema_module.federation?/0 is used as default for fragments" do
      fragment = "fragment UserFields on User { id name }"

      assert :ok =
               Validator.validate(fragment, "fragment.graphql", Test.FederationSchema, :fragment)
    end

    test "federation schema module reports federation? as true" do
      assert Test.FederationSchema.federation?() == true
    end

    test "plain schema module reports federation? as false" do
      assert Test.Schema.federation?() == false
    end
  end

  describe "validate with unfetched remote schema" do
    test "skips schema validation when remote schema is not fetched" do
      # Define a mock schema module that raises RemoteNotFetchedError
      defmodule UnfetchedRemoteSchema do
        @behaviour GraphqlQuery.Schema

        @impl true
        def schema do
          raise GraphqlQuery.Schema.RemoteNotFetchedError,
            module: __MODULE__,
            schema_path: "nonexistent/path/schema.graphql"
        end

        @impl true
        def schema_path, do: "nonexistent/path/schema.graphql"
      end

      # A valid query should pass syntax validation even though schema is unavailable
      query = "query GetUser { user { id name } }"
      assert :ok = Validator.validate(query, "test.graphql", UnfetchedRemoteSchema, :query)

      # A syntactically invalid query should still fail
      bad_query = "query T() { field }"
      assert {:error, _errors} = Validator.validate(bad_query, "test.graphql", UnfetchedRemoteSchema, :query)
    end
  end
end
