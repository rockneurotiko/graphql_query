defmodule GraphqlQuery.SchemaTest do
  use ExUnit.Case
  import GraphqlQuery
  import ExUnit.CaptureIO

  alias GraphqlQuery.{Document, Schema, Validator}

  describe "Schema behaviour" do
    test "defines required callbacks" do
      behaviours = Schema.behaviour_info(:callbacks)
      assert {:schema, 0} in behaviours
      assert {:schema_path, 0} in behaviours
    end
  end

  describe "__using__ macro with schema_path" do
    test "creates module with schema loaded from file" do
      # Create a temporary schema file
      schema_content = """
      type Query {
        user(id: ID!): User
        users: [User!]!
      }

      type User {
        id: ID!
        name: String!
        email: String!
      }
      """

      File.write!("test_schema.graphql", schema_content)

      try do
        defmodule TestSchemaModule do
          use GraphqlQuery.Schema, schema_path: "test_schema.graphql"
        end

        assert %Document{query: ^schema_content, type: :schema, path: "test_schema.graphql"} =
                 TestSchemaModule.schema()

        assert TestSchemaModule.schema_path() == "test_schema.graphql"
        assert Schema in TestSchemaModule.module_info()[:attributes][:behaviour]
      after
        File.rm("test_schema.graphql")
      end
    end

    test "validates schema file on load" do
      # Create an invalid schema file
      invalid_schema = """
      type Query {
        user(id: ID!): User
        # Invalid syntax - missing closing brace
      """

      File.write!("invalid_schema.graphql", invalid_schema)

      try do
        logs =
          capture_io(:stderr, fn ->
            defmodule TestInvalidSchemaModule do
              use GraphqlQuery.Schema, schema_path: "invalid_schema.graphql"
            end
          end)

        assert logs =~ "Validation error"
        assert logs =~ "syntax error"
      after
        File.rm("invalid_schema.graphql")
      end
    end

    test "sets schema_path to current file when not provided" do
      defmodule TestSchemaNoPath do
        use GraphqlQuery.Schema

        def schema, do: "type Query { hello: String }"
      end

      assert TestSchemaNoPath.schema_path() =~ "schema_test.exs"
    end
  end

  describe "schema validation with Validator" do
    test "validates correct GraphQL schema" do
      schema = """
      type Query {
        user(id: ID!): User
        users: [User!]!
      }

      type User {
        id: ID!
        name: String!
        email: String!
        posts: [Post!]!
      }

      type Post {
        id: ID!
        title: String!
        content: String!
        author: User!
      }
      """

      assert Validator.validate(schema, "schema.graphql", nil, :schema) == :ok
    end

    test "validates schema with interfaces" do
      schema = """
      interface Node {
        id: ID!
      }

      type User implements Node {
        id: ID!
        name: String!
        email: String!
      }

      type Post implements Node {
        id: ID!
        title: String!
        content: String!
      }

      type Query {
        node(id: ID!): Node
      }
      """

      assert Validator.validate(schema, "schema.graphql", nil, :schema) == :ok
    end

    test "validates schema with unions" do
      schema = """
      union SearchResult = User | Post

      type User {
        id: ID!
        name: String!
      }

      type Post {
        id: ID!
        title: String!
      }

      type Query {
        search(term: String!): [SearchResult!]!
      }
      """

      assert Validator.validate(schema, "schema.graphql", nil, :schema) == :ok
    end

    test "validates schema with enums" do
      schema = """
      enum UserRole {
        ADMIN
        USER
        MODERATOR
      }

      type User {
        id: ID!
        name: String!
        role: UserRole!
      }

      type Query {
        users(role: UserRole): [User!]!
      }
      """

      assert Validator.validate(schema, "schema.graphql", nil, :schema) == :ok
    end

    test "validates schema with input types" do
      schema = """
      input CreateUserInput {
        name: String!
        email: String!
        age: Int
      }

      input UpdateUserInput {
        name: String
        email: String
        age: Int
      }

      type User {
        id: ID!
        name: String!
        email: String!
        age: Int
      }

      type Query {
        user(id: ID!): User
      }

      type Mutation {
        createUser(input: CreateUserInput!): User!
        updateUser(id: ID!, input: UpdateUserInput!): User!
      }
      """

      assert Validator.validate(schema, "schema.graphql", nil, :schema) == :ok
    end

    test "validates schema with directives" do
      schema = """
      directive @auth(role: String!) on FIELD_DEFINITION

      type User {
        id: ID!
        name: String!
        email: String! @auth(role: "user")
        adminNotes: String @auth(role: "admin")
      }

      type Query {
        users: [User!]! @auth(role: "user")
        adminPanel: String @auth(role: "admin")
      }
      """

      assert Validator.validate(schema, "schema.graphql", nil, :schema) == :ok
    end

    test "expands federation directives in schema validation" do
      schema = """
      extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@shareable", "@external", "@requires"])

      type User @key(fields: "id") {
        id: ID!
        name: String! @shareable
        email: String!
      }

      type Query {
        user(id: ID!): User
      }
      """

      assert Validator.validate(schema, "schema.graphql", nil, :schema, federation: true) == :ok
    end

    test "ignore duplicated directive from @link import and explicit declaration" do
      schema = """
      extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@shareable", "@external", "@requires"])

      type User @key(fields: "id") {
        id: ID!
        name: String! @shareable
        email: String!
      }

      type Query {
        user(id: ID!): User
      }

      scalar FieldSet
      directive @key(fields: FieldSet!, resolvable: Boolean = true) repeatable on OBJECT | INTERFACE
      """

      assert Validator.validate(schema, "schema.graphql", nil, :schema, federation: true) == :ok
    end

    test "detects schema validation errors" do
      invalid_schema = """
      type Query {
        user(id: ID!): User
      }

      # Missing User type definition
      """

      assert {:error, [error]} =
               Validator.validate(invalid_schema, "schema.graphql", nil, :schema)

      assert error.message =~ "cannot find type `User` in this document"
    end

    test "detects invalid syntax in schema" do
      invalid_schema = """
      type Query {
        user(id: ID!): User
        # Missing closing brace
      """

      assert {:error, errors} = Validator.validate(invalid_schema, "schema.graphql", nil, :schema)
      assert length(errors) >= 1
      assert Enum.any?(errors, &(&1.message =~ "syntax error"))
    end

    test "detects duplicate type definitions" do
      invalid_schema = """
      type User {
        id: ID!
        name: String!
      }

      type User {
        id: ID!
        email: String!
      }

      type Query {
        user: User
      }
      """

      assert {:error, [error]} =
               Validator.validate(invalid_schema, "schema.graphql", nil, :schema)

      assert error.message =~ "the type `User` is defined multiple times in the schema"
    end

    test "validates schema with custom scalars" do
      schema = """
      scalar DateTime
      scalar JSON

      type User {
        id: ID!
        name: String!
        createdAt: DateTime!
        metadata: JSON
      }

      type Query {
        user(id: ID!): User
      }
      """

      assert Validator.validate(schema, "schema.graphql", nil, :schema) == :ok
    end
  end

  describe "~GQL sigil with schema type" do
    test "validates schema using sigil with 's' modifier" do
      document = ~GQL"""
      type Query {
        hello: String!
      }

      type User {
        id: ID!
        name: String!
      }
      """s

      assert %Document{query: schema, type: :schema} = document
      assert is_binary(schema)
      assert schema =~ "type Query"
      assert schema =~ "type User"
    end

    test "shows validation errors for invalid schema with sigil" do
      logs =
        capture_io(:stderr, fn ->
          defmodule TestInvalidSigilSchema do
            import GraphqlQuery

            def invalid_schema do
              ~GQL"""
              type Query {
                user: UnknownType
              }
              """s
            end
          end
        end)

      assert logs =~ "Validation errors"
      assert logs =~ "cannot find type `UnknownType` in this document"
    end

    test "ignores validation with 'i' modifier on schema" do
      logs =
        capture_io(:stderr, fn ->
          defmodule TestIgnoredSigilSchema do
            import GraphqlQuery

            def ignored_schema do
              ~GQL"""
              type Query {
                user: UnknownType
              }
              """si
            end
          end
        end)

      refute logs =~ "Unknown type"
    end
  end

  describe "gql macro with schema type" do
    test "validates schema with gql macro and type option" do
      defmodule TestGqlSchemaValidation do
        import GraphqlQuery

        def valid_schema do
          # Validate on runtime to avoid compile-time warning
          gql [type: :schema, runtime: true], """
          type Query {
            user(id: ID!): User
          }

          type User {
            id: ID!
            name: String!
          }
          """
        end
      end

      document = TestGqlSchemaValidation.valid_schema()
      assert %Document{query: query, type: :schema} = document
      assert query =~ "type Query"
      assert query =~ "type User"
    end

    test "shows validation errors for invalid schema with gql macro" do
      logs =
        capture_io(:stderr, fn ->
          defmodule TestInvalidGqlSchema do
            import GraphqlQuery

            def invalid_schema do
              gql [type: :schema], """
              type Query {
                user: MissingType
              }
              """
            end
          end
        end)

      assert logs =~ "Validation error"
      assert logs =~ "cannot find type `MissingType` in this document"
    end

    test "uses module-level schema configuration" do
      logs =
        capture_io(:stderr, fn ->
          defmodule TestModuleLevelSchemaConfig do
            use GraphqlQuery

            def schema_with_module_config do
              gql [type: :schema], """
              type Query {
                field: UnknownType
              }
              """
            end
          end
        end)

      assert logs =~ "cannot find type `UnknownType` in this document"
    end
  end

  describe "gql_from_file with schema type" do
    test "loads and validates schema from file" do
      schema_content = """
      type Query {
        user(id: ID!): User
        posts: [Post!]!
      }

      type User {
        id: ID!
        name: String!
        email: String!
      }

      type Post {
        id: ID!
        title: String!
        content: String!
        author: User!
      }
      """

      File.write!("test_schema_load.graphql", schema_content)

      try do
        defmodule TestSchemaFromFile do
          import GraphqlQuery

          def load_schema do
            gql_from_file("test_schema_load.graphql", type: :schema)
          end
        end

        result = TestSchemaFromFile.load_schema()
        assert %Document{query: ^schema_content, type: :schema} = result
      after
        File.rm("test_schema_load.graphql")
      end
    end

    test "validates schema from file and shows errors" do
      invalid_schema = """
      type Query {
        user: NonExistentType
      }
      """

      File.write!("invalid_schema_load.graphql", invalid_schema)

      try do
        logs =
          capture_io(:stderr, fn ->
            defmodule TestInvalidSchemaFromFile do
              import GraphqlQuery

              def load_invalid_schema do
                gql_from_file("invalid_schema_load.graphql", type: :schema)
              end
            end
          end)

        assert logs =~ "Validation error"
        assert logs =~ "cannot find type `NonExistentType` in this document"
      after
        File.rm("invalid_schema_load.graphql")
      end
    end
  end

  describe "schema integration with queries" do
    test "schema module can be used for query validation" do
      schema_content = """
      type Query {
        user(id: ID!): User
      }

      type User {
        id: ID!
        name: String!
        email: String!
      }
      """

      File.write!("user_schema.graphql", schema_content)

      try do
        defmodule UserSchema do
          use GraphqlQuery.Schema, schema_path: "user_schema.graphql"
        end

        # This should pass validation against the schema
        query = """
        query GetUser($id: ID!) {
          user(id: $id) {
            id
            name
            email
          }
        }
        """

        assert Validator.validate(query, "query.graphql", UserSchema, :query) == :ok
      after
        File.rm("user_schema.graphql")
      end
    end

    test "query validation fails against incompatible schema" do
      schema_content = """
      type Query {
        user(id: ID!): User
      }

      type User {
        id: ID!
        name: String!
      }
      """

      File.write!("limited_schema.graphql", schema_content)

      try do
        defmodule LimitedSchema do
          use GraphqlQuery.Schema, schema_path: "limited_schema.graphql"
        end

        # This query asks for an email field not defined in schema
        query = """
        query GetUser($id: ID!) {
          user(id: $id) {
            id
            name
            email
          }
        }
        """

        assert {:error, [error]} =
                 Validator.validate(query, "query.graphql", LimitedSchema, :query)

        assert error.message =~ "type `User` does not have a field `email`"
      after
        File.rm("limited_schema.graphql")
      end
    end
  end

  describe "use GraphqlQuery with schema option" do
    test "validates schema module implements behaviour" do
      valid_schema_content = """
      type Query {
        hello: String
      }
      """

      File.write!("behaviour_test_schema.graphql", valid_schema_content)

      try do
        # Define the schema module in a way that's available during compilation
        Code.compile_string("""
        defmodule ValidSchemaBehaviour do
          use GraphqlQuery.Schema, schema_path: "behaviour_test_schema.graphql"
        end
        """)

        # This should work since ValidSchemaBehaviour implements the behaviour
        [{module, _}] =
          Code.compile_string("""
          defmodule TestWithValidSchema do
            use GraphqlQuery, schema: ValidSchemaBehaviour

            def test_query do
              ~GQL"query { hello }"
            end
          end
          """)

        assert %Document{type: :query, query: "query { hello }", schema: ValidSchemaBehaviour} =
                 module.test_query()
      after
        File.rm("behaviour_test_schema.graphql")
      end
    end

    test "raises error when schema module doesn't implement behaviour" do
      # Create a module that doesn't implement the Schema behaviour
      Code.compile_string("""
      defmodule NotASchemaModule do
        def some_function, do: "not a schema"
      end
      """)

      assert_raise ArgumentError, ~r/must implement GraphqlQuery.Schema behaviour/, fn ->
        Code.compile_string("""
        defmodule TestWithInvalidSchema do
          use GraphqlQuery, schema: NotASchemaModule
        end
        """)
      end
    end
  end
end
