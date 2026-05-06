defmodule GraphqlQuery.Schema.Remote.IntrospectionTest do
  use ExUnit.Case, async: true

  alias GraphqlQuery.Schema.Remote.Introspection

  @fixture_path "test/fixtures/introspection.json"

  defp load_fixture do
    @fixture_path |> File.read!() |> Jason.decode!()
  end

  describe "to_sdl/1" do
    test "converts full introspection response to valid SDL" do
      json = load_fixture()
      assert {:ok, sdl} = Introspection.to_sdl(json)
      assert is_binary(sdl)
      assert String.length(sdl) > 0

      # Validate the generated SDL parses correctly
      assert {:ok, _} = GraphqlQuery.Native.validate_schema(sdl, "test.graphql")
    end

    test "accepts response with data wrapper" do
      json = load_fixture()
      assert {:ok, sdl} = Introspection.to_sdl(json)
      assert String.contains?(sdl, "type Query")
    end

    test "accepts response without data wrapper" do
      json = load_fixture()
      schema = json["data"]
      assert {:ok, sdl} = Introspection.to_sdl(schema)
      assert String.contains?(sdl, "type Query")
    end

    test "accepts bare schema map" do
      json = load_fixture()
      schema = json["data"]["__schema"]
      assert {:ok, sdl} = Introspection.to_sdl(schema)
      assert String.contains?(sdl, "type Query")
    end

    test "returns error for invalid input" do
      assert {:error, _} = Introspection.to_sdl(%{"invalid" => "data"})
    end

    test "generates scalar types (non-builtin only)" do
      # The graphqlzero API has no custom scalars — verify built-ins are suppressed
      json = load_fixture()
      {:ok, sdl} = Introspection.to_sdl(json)

      # Built-in scalars should NOT be defined
      refute sdl =~ ~r/^scalar String$/m
      refute sdl =~ ~r/^scalar Int$/m
      refute sdl =~ ~r/^scalar Float$/m
      refute sdl =~ ~r/^scalar Boolean$/m
      refute sdl =~ ~r/^scalar ID$/m
    end

    test "generates object types with fields" do
      json = load_fixture()
      {:ok, sdl} = Introspection.to_sdl(json)

      assert sdl =~ "type Album {"
      assert sdl =~ "id: ID"
      assert sdl =~ "title: String"
    end

    test "generates input types" do
      json = load_fixture()
      {:ok, sdl} = Introspection.to_sdl(json)

      assert sdl =~ "input CreateAlbumInput {"
    end

    test "generates enum types" do
      json = load_fixture()
      {:ok, sdl} = Introspection.to_sdl(json)

      assert sdl =~ "enum SortOrderEnum {"
      assert sdl =~ "ASC"
      assert sdl =~ "DESC"
    end

    test "generates directives" do
      json = load_fixture()
      {:ok, sdl} = Introspection.to_sdl(json)

      # All directives including built-ins
      assert sdl =~ "directive @deprecated"
      assert sdl =~ "directive @include"
      assert sdl =~ "directive @skip"
      assert sdl =~ "directive @specifiedBy"
    end

    test "handles NON_NULL type wrapping" do
      # Query.album(id: ID!) has a NON_NULL arg
      json = load_fixture()
      {:ok, sdl} = Introspection.to_sdl(json)

      assert sdl =~ "album("
      assert sdl =~ "id: ID!"
    end

    test "handles LIST type wrapping" do
      json = load_fixture()
      {:ok, sdl} = Introspection.to_sdl(json)

      # PostsPage.data is [Post]
      assert sdl =~ "[Post]"
    end

    test "skips introspection types (__Type, __Schema, etc.)" do
      json = load_fixture()
      {:ok, sdl} = Introspection.to_sdl(json)

      refute sdl =~ "type __Type"
      refute sdl =~ "type __Schema"
      refute sdl =~ "type __Field"
      refute sdl =~ "enum __TypeKind"
    end

    test "generates field arguments" do
      json = load_fixture()
      {:ok, sdl} = Introspection.to_sdl(json)

      # Query.album and Query.user have an id arg
      assert sdl =~ "album("
      assert sdl =~ "user("
    end

    test "generates default values for arguments" do
      # Use a synthetic schema since graphqlzero has no user-facing default values
      schema = %{
        "queryType" => %{"name" => "Query"},
        "mutationType" => nil,
        "subscriptionType" => nil,
        "types" => [
          %{
            "kind" => "OBJECT",
            "name" => "Query",
            "description" => nil,
            "fields" => [
              %{
                "name" => "users",
                "description" => nil,
                "args" => [
                  %{
                    "name" => "status",
                    "description" => nil,
                    "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                    "defaultValue" => ~s(["active"])
                  }
                ],
                "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ],
            "inputFields" => nil,
            "interfaces" => [],
            "enumValues" => nil,
            "possibleTypes" => nil
          }
        ],
        "directives" => []
      }

      {:ok, sdl} = Introspection.to_sdl(schema)
      assert sdl =~ ~s(= ["active"])
    end

    test "generates deprecation annotations" do
      json = load_fixture()
      {:ok, sdl} = Introspection.to_sdl(json)

      # The @deprecated directive is present in all schemas
      assert sdl =~ "directive @deprecated"
    end

    test "escapes control characters in deprecation reasons so the SDL parses" do
      schema = %{
        "queryType" => %{"name" => "Query"},
        "mutationType" => nil,
        "subscriptionType" => nil,
        "directives" => [],
        "types" => [
          %{
            "kind" => "OBJECT",
            "name" => "Query",
            "description" => nil,
            "interfaces" => [],
            "fields" => [
              %{
                "name" => "old",
                "description" => nil,
                "args" => [],
                "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                "isDeprecated" => true,
                "deprecationReason" => "Use `new` instead.\nSee the docs for details.\n"
              }
            ],
            "inputFields" => nil,
            "enumValues" => nil,
            "possibleTypes" => nil
          }
        ]
      }

      {:ok, sdl} = Introspection.to_sdl(schema)
      assert sdl =~ ~S|@deprecated(reason: "Use `new` instead.\nSee the docs for details.\n")|
      assert {:ok, _} = GraphqlQuery.Native.validate_schema(sdl, "test.graphql")
    end

    test "escapes the full set of GraphQL StringValue escapes in deprecation reasons" do
      reason =
        "quote:\" backslash:\\ bs:\b ff:\f lf:\n cr:\r tab:\t soh:\x01 nel:\u0085 unicode:café"

      schema = %{
        "queryType" => %{"name" => "Query"},
        "mutationType" => nil,
        "subscriptionType" => nil,
        "directives" => [],
        "types" => [
          %{
            "kind" => "OBJECT",
            "name" => "Query",
            "description" => nil,
            "interfaces" => [],
            "fields" => [
              %{
                "name" => "old",
                "description" => nil,
                "args" => [],
                "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                "isDeprecated" => true,
                "deprecationReason" => reason
              }
            ],
            "inputFields" => nil,
            "enumValues" => nil,
            "possibleTypes" => nil
          }
        ]
      }

      {:ok, sdl} = Introspection.to_sdl(schema)

      expected =
        "@deprecated(reason: \"quote:\\\" backslash:\\\\ bs:\\b ff:\\f lf:\\n cr:\\r tab:\\t soh:\\u0001 nel:\\u0085 unicode:café\")"

      assert sdl =~ expected
      assert {:ok, _} = GraphqlQuery.Native.validate_schema(sdl, "test.graphql")
    end

    test "does not emit schema definition for standard root type names" do
      json = load_fixture()
      {:ok, sdl} = Introspection.to_sdl(json)

      # Query and Mutation are standard names, so no schema {} block
      refute sdl =~ ~r/^schema \{/m
    end

    test "emits schema definition for non-standard root type names" do
      schema = %{
        "queryType" => %{"name" => "RootQuery"},
        "mutationType" => %{"name" => "RootMutation"},
        "subscriptionType" => nil,
        "types" => [
          %{
            "kind" => "OBJECT",
            "name" => "RootQuery",
            "description" => nil,
            "fields" => [
              %{
                "name" => "hello",
                "description" => nil,
                "args" => [],
                "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ],
            "inputFields" => nil,
            "interfaces" => [],
            "enumValues" => nil,
            "possibleTypes" => nil
          },
          %{
            "kind" => "OBJECT",
            "name" => "RootMutation",
            "description" => nil,
            "fields" => [
              %{
                "name" => "doSomething",
                "description" => nil,
                "args" => [],
                "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ],
            "inputFields" => nil,
            "interfaces" => [],
            "enumValues" => nil,
            "possibleTypes" => nil
          }
        ],
        "directives" => []
      }

      {:ok, sdl} = Introspection.to_sdl(schema)
      assert sdl =~ "schema {"
      assert sdl =~ "query: RootQuery"
      assert sdl =~ "mutation: RootMutation"
    end

    test "handles interface types" do
      schema = %{
        "queryType" => %{"name" => "Query"},
        "mutationType" => nil,
        "subscriptionType" => nil,
        "types" => [
          %{
            "kind" => "INTERFACE",
            "name" => "Node",
            "description" => "An object with an ID",
            "fields" => [
              %{
                "name" => "id",
                "description" => nil,
                "args" => [],
                "type" => %{
                  "kind" => "NON_NULL",
                  "name" => nil,
                  "ofType" => %{"kind" => "SCALAR", "name" => "ID", "ofType" => nil}
                },
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ],
            "inputFields" => nil,
            "interfaces" => nil,
            "enumValues" => nil,
            "possibleTypes" => [%{"kind" => "OBJECT", "name" => "User"}]
          },
          %{
            "kind" => "OBJECT",
            "name" => "User",
            "description" => nil,
            "fields" => [
              %{
                "name" => "id",
                "description" => nil,
                "args" => [],
                "type" => %{
                  "kind" => "NON_NULL",
                  "name" => nil,
                  "ofType" => %{"kind" => "SCALAR", "name" => "ID", "ofType" => nil}
                },
                "isDeprecated" => false,
                "deprecationReason" => nil
              },
              %{
                "name" => "name",
                "description" => nil,
                "args" => [],
                "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ],
            "inputFields" => nil,
            "interfaces" => [%{"kind" => "INTERFACE", "name" => "Node"}],
            "enumValues" => nil,
            "possibleTypes" => nil
          },
          %{
            "kind" => "OBJECT",
            "name" => "Query",
            "description" => nil,
            "fields" => [
              %{
                "name" => "node",
                "description" => nil,
                "args" => [
                  %{
                    "name" => "id",
                    "description" => nil,
                    "type" => %{
                      "kind" => "NON_NULL",
                      "name" => nil,
                      "ofType" => %{"kind" => "SCALAR", "name" => "ID", "ofType" => nil}
                    },
                    "defaultValue" => nil
                  }
                ],
                "type" => %{"kind" => "INTERFACE", "name" => "Node", "ofType" => nil},
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ],
            "inputFields" => nil,
            "interfaces" => [],
            "enumValues" => nil,
            "possibleTypes" => nil
          }
        ],
        "directives" => []
      }

      {:ok, sdl} = Introspection.to_sdl(schema)
      assert sdl =~ "interface Node {"
      assert sdl =~ "id: ID!"
      assert sdl =~ "type User implements Node {"
    end

    test "handles union types" do
      schema = %{
        "queryType" => %{"name" => "Query"},
        "mutationType" => nil,
        "subscriptionType" => nil,
        "types" => [
          %{
            "kind" => "UNION",
            "name" => "SearchResult",
            "description" => "A search result",
            "fields" => nil,
            "inputFields" => nil,
            "interfaces" => nil,
            "enumValues" => nil,
            "possibleTypes" => [
              %{"kind" => "OBJECT", "name" => "User"},
              %{"kind" => "OBJECT", "name" => "Post"}
            ]
          },
          %{
            "kind" => "OBJECT",
            "name" => "User",
            "description" => nil,
            "fields" => [
              %{
                "name" => "name",
                "description" => nil,
                "args" => [],
                "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ],
            "inputFields" => nil,
            "interfaces" => [],
            "enumValues" => nil,
            "possibleTypes" => nil
          },
          %{
            "kind" => "OBJECT",
            "name" => "Post",
            "description" => nil,
            "fields" => [
              %{
                "name" => "title",
                "description" => nil,
                "args" => [],
                "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ],
            "inputFields" => nil,
            "interfaces" => [],
            "enumValues" => nil,
            "possibleTypes" => nil
          },
          %{
            "kind" => "OBJECT",
            "name" => "Query",
            "description" => nil,
            "fields" => [
              %{
                "name" => "search",
                "description" => nil,
                "args" => [],
                "type" => %{"kind" => "UNION", "name" => "SearchResult", "ofType" => nil},
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ],
            "inputFields" => nil,
            "interfaces" => [],
            "enumValues" => nil,
            "possibleTypes" => nil
          }
        ],
        "directives" => []
      }

      {:ok, sdl} = Introspection.to_sdl(schema)
      assert sdl =~ "union SearchResult = User | Post"
    end

    test "handles descriptions on types and fields" do
      schema = %{
        "queryType" => %{"name" => "Query"},
        "mutationType" => nil,
        "subscriptionType" => nil,
        "types" => [
          %{
            "kind" => "OBJECT",
            "name" => "Query",
            "description" => "The root query type",
            "fields" => [
              %{
                "name" => "hello",
                "description" => "A greeting",
                "args" => [],
                "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ],
            "inputFields" => nil,
            "interfaces" => [],
            "enumValues" => nil,
            "possibleTypes" => nil
          }
        ],
        "directives" => []
      }

      {:ok, sdl} = Introspection.to_sdl(schema)
      assert sdl =~ ~s("""The root query type""")
      assert sdl =~ ~s("""A greeting""")
    end

    test "uses multi-line block string when description ends with a quote" do
      schema = %{
        "queryType" => %{"name" => "Query"},
        "mutationType" => nil,
        "subscriptionType" => nil,
        "types" => [
          %{
            "kind" => "OBJECT",
            "name" => "Query",
            "description" => nil,
            "fields" => [
              %{
                "name" => "profile",
                "description" => ~s(The identifier, also known as "DK"),
                "args" => [],
                "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                "isDeprecated" => false,
                "deprecationReason" => nil
              },
              %{
                "name" => "customer",
                "description" => ~s(Also known as "Customer Number"),
                "args" => [],
                "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ],
            "inputFields" => nil,
            "interfaces" => [],
            "enumValues" => nil,
            "possibleTypes" => nil
          }
        ],
        "directives" => []
      }

      {:ok, sdl} = Introspection.to_sdl(schema)

      # Must NOT produce """..."DK"""" (four quotes) — use multi-line format instead
      refute sdl =~ ~s("""")

      # Multi-line format: opening """ on its own line, content on next, closing """ on its own line
      # (with field-level indentation prefix)
      assert sdl =~ ~s(  \"\"\"\n  The identifier, also known as \"DK\"\n  \"\"\")
      assert sdl =~ ~s(  \"\"\"\n  Also known as \"Customer Number\"\n  \"\"\")

      # The generated SDL must be valid GraphQL
      assert {:ok, _} = GraphqlQuery.Native.validate_schema(sdl, "quoted_descriptions.graphql")
    end

    test "uses multi-line block string when description starts with a quote" do
      schema = %{
        "queryType" => %{"name" => "Query"},
        "mutationType" => nil,
        "subscriptionType" => nil,
        "types" => [
          %{
            "kind" => "OBJECT",
            "name" => "Query",
            "description" => ~s(\"Special\" query type),
            "fields" => [
              %{
                "name" => "hello",
                "description" => nil,
                "args" => [],
                "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ],
            "inputFields" => nil,
            "interfaces" => [],
            "enumValues" => nil,
            "possibleTypes" => nil
          }
        ],
        "directives" => []
      }

      {:ok, sdl} = Introspection.to_sdl(schema)

      # Must use multi-line format
      refute sdl =~ ~s("""")

      # The generated SDL must be valid GraphQL
      assert {:ok, _} =
               GraphqlQuery.Native.validate_schema(sdl, "leading_quote_descriptions.graphql")
    end

    test "handles deprecated fields with reason" do
      schema = %{
        "queryType" => %{"name" => "Query"},
        "mutationType" => nil,
        "subscriptionType" => nil,
        "types" => [
          %{
            "kind" => "OBJECT",
            "name" => "Query",
            "description" => nil,
            "fields" => [
              %{
                "name" => "oldField",
                "description" => nil,
                "args" => [],
                "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                "isDeprecated" => true,
                "deprecationReason" => "Use newField instead"
              },
              %{
                "name" => "newField",
                "description" => nil,
                "args" => [],
                "type" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil},
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ],
            "inputFields" => nil,
            "interfaces" => [],
            "enumValues" => nil,
            "possibleTypes" => nil
          }
        ],
        "directives" => []
      }

      {:ok, sdl} = Introspection.to_sdl(schema)
      assert sdl =~ ~s|oldField: String @deprecated(reason: "Use newField instead")|
    end

    test "handles deprecated enum values" do
      schema = %{
        "queryType" => %{"name" => "Query"},
        "mutationType" => nil,
        "subscriptionType" => nil,
        "types" => [
          %{
            "kind" => "ENUM",
            "name" => "Status",
            "description" => nil,
            "fields" => nil,
            "inputFields" => nil,
            "interfaces" => nil,
            "enumValues" => [
              %{
                "name" => "ACTIVE",
                "description" => nil,
                "isDeprecated" => false,
                "deprecationReason" => nil
              },
              %{
                "name" => "INACTIVE",
                "description" => nil,
                "isDeprecated" => true,
                "deprecationReason" => "Use DISABLED"
              }
            ],
            "possibleTypes" => nil
          },
          %{
            "kind" => "OBJECT",
            "name" => "Query",
            "description" => nil,
            "fields" => [
              %{
                "name" => "status",
                "description" => nil,
                "args" => [],
                "type" => %{"kind" => "ENUM", "name" => "Status", "ofType" => nil},
                "isDeprecated" => false,
                "deprecationReason" => nil
              }
            ],
            "inputFields" => nil,
            "interfaces" => [],
            "enumValues" => nil,
            "possibleTypes" => nil
          }
        ],
        "directives" => []
      }

      {:ok, sdl} = Introspection.to_sdl(schema)
      assert sdl =~ ~s|INACTIVE @deprecated(reason: "Use DISABLED")|
    end

    test "round-trip: introspection JSON -> SDL -> validates as schema" do
      json = load_fixture()
      {:ok, sdl} = Introspection.to_sdl(json)

      # The SDL should be parseable as a valid GraphQL schema
      assert {:ok, _} =
               GraphqlQuery.Native.validate_schema(sdl, "introspection_roundtrip.graphql")
    end
  end

  describe "introspection_query/0" do
    test "returns a valid GraphQL query string" do
      document = Introspection.introspection_query()
      assert %GraphqlQuery.Document{} = document
      assert document.name == "IntrospectionQuery"

      assert document.query =~ "query IntrospectionQuery"
      assert document.query =~ "__schema"
      assert document.query =~ "queryType"
      assert document.query =~ "mutationType"
      assert document.query =~ "subscriptionType"
      assert document.query =~ "description"
      assert document.query =~ "isRepeatable"
    end
  end
end
