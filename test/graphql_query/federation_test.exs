defmodule GraphqlQuery.FederationTest do
  use ExUnit.Case

  use GraphqlQuery

  alias GraphqlQuery.Document
  import ExUnit.CaptureLog
  import ExUnit.CaptureIO

  describe "basic federation validation" do
    test "warning on federation directives missing federation flag" do
      query_ast =
        quote do
          import GraphqlQuery

          ~GQL"""
          schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key"]) {
            query: RootQueryType
          }

          type RootQueryType {
            vehicle(id: ID!): Vehicle
          }

          type Vehicle @key(fields: "id") {
            id: ID!
            type: String
          }
          """s
        end

      logs =
        capture_io(:stderr, fn ->
          {query, _} = Code.eval_quoted(query_ast)

          assert %Document{type: :schema} = query
        end)

      assert logs =~ "cannot find directive `@link` in this document"
      assert logs =~ "cannot find directive `@key` in this document"
    end

    test "ok on federation directives with federation flag" do
      query_ast =
        quote do
          import GraphqlQuery

          ~GQL"""
          schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key"]) {
            query: RootQueryType
          }

          type RootQueryType {
            vehicle(id: ID!): Vehicle
          }

          type Vehicle @key(fields: "id") {
            id: ID!
            type: String
          }
          """sF
        end

      logs =
        capture_io(:stderr, fn ->
          {query, _} = Code.eval_quoted(query_ast)

          assert %Document{type: :schema} = query
        end)

      assert logs == ""
    end

    test "validates basic federation schema with sigil F modifier" do
      schema =
        ~GQL"""
        extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@shareable"])

        type Query {
          user(id: ID!): User
        }

        type User @key(fields: "id") {
          id: ID!
          name: String! @shareable
        }
        """sF

      assert %Document{type: :schema} = schema
    end

    test "warns without F modifier" do
      query_ast =
        quote do
          import GraphqlQuery

          ~GQL"""
          extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@shareable"])

          type Query {
            user(id: ID!): User
          }

          type User @key(fields: "id") {
            id: ID!
            name: String! @shareable
          }
          """s
        end

      logs =
        capture_io(:stderr, fn ->
          {schema, _} = Code.eval_quoted(query_ast)
          assert %Document{type: :schema} = schema
        end)

      assert logs =~ "cannot find directive `@link`"
    end
  end

  describe "federation - document_with_options" do
    test "validates with federation: true option" do
      document_with_options type: :schema, federation: true do
        schema =
          ~GQL"""
          extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@shareable"])

          type Query {
            user(id: ID!): User
          }

          type User @key(fields: "id") {
            id: ID!
            name: String! @shareable
          }
          """s

        assert %Document{type: :schema} = schema
      end
    end

    test "warns without federation option" do
      query_ast =
        quote do
          import GraphqlQuery

          document_with_options type: :schema do
            ~GQL"""
            extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@shareable"])

            type Query {
              user(id: ID!): User
            }

            type User @key(fields: "id") {
              id: ID!
              name: String! @shareable
            }
            """s
          end
        end

      logs =
        capture_io(:stderr, fn ->
          {schema, _} = Code.eval_quoted(query_ast)
          assert %Document{type: :schema} = schema
        end)

      assert logs =~ "cannot find directive"
    end
  end

  describe "federation - gql macro" do
    test "validates with federation: true" do
      url = "https://specs.apollo.dev/federation/v2.0"

      schema =
        gql [type: :schema, federation: true, runtime: true], """
        extend schema
          @link(url: "#{url}", import: ["@key", "@shareable"])

        type Query {
          user(id: ID!): User
        }

        type User @key(fields: "id") {
          id: ID!
          name: String! @shareable
        }
        """

      assert %Document{type: :schema} = schema
    end

    test "warns without federation flag using runtime validation" do
      # Use runtime: true to validate at runtime
      logs =
        capture_log(fn ->
          schema =
            gql [type: :schema, runtime: true], """
            extend schema
              @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@shareable"])

            type Query {
              user(id: ID!): User
            }

            type User @key(fields: "id") {
              id: ID!
              name: String! @shareable
            }
            """

          # With runtime validation and no federation flag, the schema is still created
          # but validation errors are logged
          assert %Document{type: :schema} = schema
        end)

      assert logs =~ "cannot find directive `@link` in this document"
      assert logs =~ "cannot find directive `@key` in this document"
    end
  end

  describe "federation - gql_from_file" do
    @federation_schema_file "test/fixtures/federation_schema.graphql"

    test "validates with federation: true" do
      logs =
        capture_log(fn ->
          schema = gql_from_file(@federation_schema_file, type: :schema, federation: true)
          assert %Document{type: :schema} = schema
        end)

      assert logs == ""
    end

    test "warns without federation flag using runtime validation" do
      logs =
        capture_log(fn ->
          schema = gql_from_file(@federation_schema_file, type: :schema, runtime: true)

          assert %Document{type: :schema} = schema
        end)

      assert logs =~ "cannot find directive `@link` in this document"
      assert logs =~ "cannot find directive `@key` in this document"
    end
  end

  describe "federation - module-level option" do
    defmodule TestModuleFederation do
      use GraphqlQuery, federation: true

      def schema do
        ~GQL"""
        extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key"])

        type Query {
          user(id: ID!): User
        }

        type User @key(fields: "id") {
          id: ID!
          name: String!
        }
        """s
      end
    end

    test "uses module-level federation option" do
      schema = TestModuleFederation.schema()
      assert %Document{type: :schema} = schema
    end
  end

  describe "federation - renamed directives" do
    test "allows using renamed directives" do
      schema =
        ~GQL"""
        extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: [{name: "@key", as: "@primaryKey"}, "@shareable"])

        type Query {
          product(id: ID!): Product
        }

        type Product @primaryKey(fields: "id") {
          id: ID!
          name: String! @shareable
        }
        """sF

      assert %Document{type: :schema} = schema
    end

    test "renamed directives require using the renamed name" do
      # When you rename @key to @primaryKey, you must use @primaryKey
      # (This tests the actual behavior, not the simplified implementation note)
      query_ast =
        quote do
          import GraphqlQuery

          ~GQL"""
          extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: [{name: "@key", as: "@primaryKey"}])

          type Query {
            product(id: ID!): Product
          }

          type Product @key(fields: "id") {
            id: ID!
            name: String!
          }
          """sF
        end

      logs =
        capture_io(:stderr, fn ->
          {schema, _} = Code.eval_quoted(query_ast)
          assert %Document{type: :schema} = schema
        end)

      # The original @key name is not available after renaming
      assert logs =~ "cannot find directive `@key`"
    end
  end

  describe "federation - custom prefix" do
    test "allows using directives with custom prefix" do
      schema =
        ~GQL"""
        extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key"], as: "fed")

        type Query {
          order(id: ID!): Order
        }

        type Order @key(fields: "id") {
          id: ID!
          total: Float
        }
        """sF

      assert %Document{type: :schema} = schema
    end

    test "custom prefix requires using the prefix for non-imported directives" do
      # When you set a custom prefix, non-imported directives use that prefix
      query_ast =
        quote do
          import GraphqlQuery

          ~GQL"""
          extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key"], as: "fed")

          type Query {
            order(id: ID!): Order
          }

          type Order @key(fields: "id") {
            id: ID!
            total: Float @federation__shareable
          }
          """sF
        end

      logs =
        capture_io(:stderr, fn ->
          {schema, _} = Code.eval_quoted(query_ast)
          assert %Document{type: :schema} = schema
        end)

      # With custom prefix "fed", non-imported directives should use @fed__ not @federation__
      assert logs =~ "cannot find directive `@federation__shareable`"
    end
  end

  describe "federation - namespaced directives" do
    test "allows using fully namespaced directives" do
      schema =
        ~GQL"""
        extend schema @link(url: "https://specs.apollo.dev/federation/v2.0")

        type Query {
          item(id: ID!): Item
        }

        type Item @federation__key(fields: "id") {
          id: ID!
          name: String!
        }
        """sF

      assert %Document{type: :schema} = schema
    end

    test "when no imports specified, must use namespaced directive names" do
      # When no imports are specified, directives must be used with namespace prefix
      query_ast =
        quote do
          import GraphqlQuery

          ~GQL"""
          extend schema @link(url: "https://specs.apollo.dev/federation/v2.0")

          type Query {
            item(id: ID!): Item
          }

          type Item @federation__key(fields: "id") {
            id: ID!
            name: String! @shareable
          }
          """sF
        end

      logs =
        capture_io(:stderr, fn ->
          {schema, _} = Code.eval_quoted(query_ast)
          assert %Document{type: :schema} = schema
        end)

      # Without imports, short names are not available
      assert logs =~ "cannot find directive `@shareable`"
    end
  end

  describe "federation - version support" do
    test "supports federation v2.0 directives" do
      schema = ~GQL"""
      extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@external"])

      type Query {
        user(id: ID!): User
      }

      type User @key(fields: "id") {
        id: ID!
        name: String! @external
      }
      """sF

      assert %Document{type: :schema} = schema
    end

    test "supports federation v2.5 with authentication directives" do
      schema = ~GQL"""
      extend schema @link(url: "https://specs.apollo.dev/federation/v2.5", import: ["@key", "@authenticated", "@requiresScopes"])

      type Query {
        user(id: ID!): User
      }

      type User @key(fields: "id") @authenticated {
        id: ID!
        email: String! @requiresScopes(scopes: [["read:email"]])
      }
      """sF

      assert %Document{type: :schema} = schema
    end

    test "supports federation v2.9 with cost directives" do
      schema = ~GQL"""
      extend schema @link(url: "https://specs.apollo.dev/federation/v2.9", import: ["@key", "@cost", "@listSize"])

      type Query {
        users: [User!]! @listSize(assumedSize: 100)
      }

      type User @key(fields: "id") {
        id: ID!
        name: String! @cost(weight: 1)
      }
      """sF

      assert %Document{type: :schema} = schema
    end

    test "falls back to standard validation for unknown versions" do
      query_ast =
        quote do
          import GraphqlQuery

          ~GQL"""
          extend schema @link(url: "https://specs.apollo.dev/federation/v99.0", import: ["@key"])

          type Query {
            user(id: ID!): User
          }

          type User @key(fields: "id") {
            id: ID!
            name: String!
          }
          """sF
        end

      logs =
        capture_io(:stderr, fn ->
          {schema, _} = Code.eval_quoted(query_ast)
          assert %Document{type: :schema} = schema
        end)

      # Unknown version falls back to standard validation, so directives won't be found
      assert logs =~ "cannot find directive `@key`"
    end
  end

  describe "federation - use GraphqlQuery.Schema" do
    @federation_file "test/fixtures/federation_schema.graphql"

    test "schema_path with federation: true produces no warnings" do
      logs =
        capture_io(:stderr, fn ->
          Code.eval_quoted(
            quote do
              defmodule TestSchemaPathFederation do
                use GraphqlQuery.Schema,
                  schema_path: unquote(@federation_file),
                  federation: true
              end
            end
          )
        end)

      assert logs == ""
    end

    test "schema_path without federation: true warns on federation directives" do
      logs =
        capture_io(:stderr, fn ->
          Code.eval_quoted(
            quote do
              defmodule TestSchemaPathNoFederation do
                use GraphqlQuery.Schema,
                  schema_path: unquote(@federation_file)
              end
            end
          )
        end)

      assert logs =~ "cannot find directive"
    end
  end

  describe "federation - @link spec itself" do
    test "validates @link directive definition" do
      schema = ~GQL"""
      extend schema @link(url: "https://specs.apollo.dev/link/v1.0") @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key"])

      type Query {
        user(id: ID!): User
      }

      type User @key(fields: "id") {
        id: ID!
      }
      """sF

      assert %Document{type: :schema} = schema
    end

    test "@link directive is available even without explicit @link import" do
      schema = ~GQL"""
      extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key"])

      type Query {
        user(id: ID!): User
      }

      type User @key(fields: "id") {
        id: ID!
      }
      """sF

      assert %Document{type: :schema} = schema
    end
  end

  describe "federation - multiple directives" do
    test "supports multiple federation directives on same type" do
      schema = ~GQL"""
      extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@shareable", "@tag"])

      type Query {
        product(id: ID!): Product
      }

      type Product @key(fields: "id") @tag(name: "public") {
        id: ID!
        name: String! @shareable
        price: Float @shareable @tag(name: "pricing")
      }
      """sF

      assert %Document{type: :schema} = schema
    end

    test "supports complex federation schema with multiple entity types" do
      schema = ~GQL"""
      extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@shareable", "@external", "@requires", "@provides"])

      type Query {
        user(id: ID!): User
        product(id: ID!): Product
      }

      type User @key(fields: "id") {
        id: ID!
        username: String! @shareable
        email: String!
        reviews: [Review!]!
      }

      type Product @key(fields: "id") {
        id: ID!
        name: String!
        price: Float
      }

      type Review @key(fields: "id") {
        id: ID!
        rating: Int!
        content: String
        author: User! @provides(fields: "username")
        product: Product!
      }
      """sF

      assert %Document{type: :schema} = schema
    end
  end
end
