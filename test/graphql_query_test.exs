defmodule GraphqlQueryTest do
  use ExUnit.Case
  import GraphqlQuery
  doctest GraphqlQuery

  alias GraphqlQuery.{Document, Fragment}

  describe "document_with_options/2" do
    test "adds options to ~GQL sigil" do
      query =
        document_with_options ignore: true do
          ~GQL"""
          query GetUser($id: ID!) {
            user(id: $id) {
              id
              name
            }
          }
          """
        end

      assert %Document{query: result, type: :query} = query
      assert result =~ "query GetUser($id: ID!)"
      assert result =~ "user(id: $id)"
    end

    test "adds options to ~GQL sigil with modifiers" do
      query =
        document_with_options ignore: true do
          ~GQL"""
          fragment UserFragment on User {
            id
            name
            email
          }
          """f
        end

      assert %Fragment{fragment: result} = query
      assert result =~ "fragment UserFragment on User"
    end

    test "adds runtime option to ~GQL sigil" do
      # Should not validate at compile time but return the document
      query =
        document_with_options runtime: true do
          ~GQL"""
          query GetUser($id: ID!) {
            user(id: $id) {
              ...NonExistentFragment
            }
          }
          """
        end

      assert %Document{query: result, type: :query} = query
      assert result =~ "...NonExistentFragment"
    end

    test "options precedence - sigil modifiers override document_with_options" do
      query =
        document_with_options type: :query do
          ~GQL"""
          fragment UserFragment on User {
            id
            name
          }
          """f
        end

      # The 'f' modifier should take precedence over type: :query
      assert %Fragment{} = query
    end

    test "adds options to gql macro with static content" do
      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          query =
            document_with_options ignore: true do
              gql """
              query GetUser($id: ID!) {
                user(id: $id) {
                  id
                  name
                }
              }
              """
            end

          assert %Document{query: result, type: :query} = query
          assert result =~ "query GetUser($id: ID!)"
        end)

      # Should not have any warnings because ignore: true was applied
      refute logs =~ "[GraphqlQuery]"
    end

    test "adds options to gql macro with existing options" do
      defmodule TestGqlEvaluate1 do
        import GraphqlQuery

        defmodule TestFieldHelper do
          def test_field, do: "email"
        end

        def query do
          document_with_options evaluate: true do
            gql [type: :query], """
            query GetUser($id: ID!) {
              user(id: $id) {
                id
                name
                #{TestFieldHelper.test_field()}
              }
            }
            """
          end
        end
      end

      assert %Document{query: result, type: :query} = TestGqlEvaluate1.query()
      assert result =~ "email"
    end

    test "options precedence - explicit gql options override document_with_options" do
      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          query_ast =
            quote do
              document_with_options ignore: true do
                gql [ignore: false], """
                query GetUser($unused: String) {
                  user {
                    id
                  }
                }
                """
              end
            end

          {query, _} = Code.eval_quoted(query_ast)

          assert %Document{} = query
        end)

      # Should have warnings because ignore: false overrides ignore: true
      assert logs =~ "unused variable"
    end

    test "adds options to gql macro with dynamic content" do
      defmodule TestGqlEvaluate2 do
        import GraphqlQuery

        defmodule TestHelper do
          def get_fields, do: "id name email"
        end

        def query do
          document_with_options evaluate: true do
            gql """
            query GetUser {
              user {
            #{TestHelper.get_fields()}
              }
            }
            """
          end
        end
      end

      assert %Document{query: result, type: :query} = TestGqlEvaluate2.query()
      assert result =~ "id name email"
    end

    test "adds runtime option to gql macro with local variables" do
      query =
        document_with_options runtime: true do
          fields = ["id", "name", "email"]

          gql """
          query GetUser {
            user {
              #{Enum.join(fields, "\n")}
            }
          }
          """
        end

      assert %Document{query: result, type: :query} = query
      assert result =~ "id\nname\nemail"
    end

    test "multiple gql calls in same document_with_options block" do
      queries =
        document_with_options ignore: true do
          [
            gql("query { user { id } }"),
            gql("query { posts { title } }"),
            ~GQL"{
  comments {
    content
  }
}
"
          ]
        end

      assert [%Document{}, %Document{}, %Document{}] = queries
      assert Enum.all?(queries, fn %Document{type: type} -> type == :query end)
    end

    test "nested expressions with gql calls" do
      result =
        document_with_options ignore: true do
          case :query do
            :query ->
              gql "query { user { id name } }"

            :fragment ->
              ~GQL"fragment User on User {
  id
}
"f
          end
        end

      assert %Document{query: query_str, type: :query} = result
      assert query_str =~ "query { user { id name } }"
    end

    test "adds options to gql_from_file macro" do
      query =
        document_with_options ignore: true do
          gql_from_file("test/fixtures/test_query.graphql")
        end

      assert %Document{query: result, type: :query} = query
      assert result =~ "query GetUser($id: ID!)"
      assert result =~ "user(id: $id)"
    end

    test "adds options to gql_from_file with existing options" do
      fragment =
        document_with_options ignore: true do
          gql_from_file("test/fixtures/test_fragment.graphql", type: :fragment)
        end

      assert %Fragment{fragment: result} = fragment
      assert result =~ "fragment UserFields on User"
    end

    test "options precedence - explicit gql_from_file options override document_with_options" do
      # It needs to be in a module, because gql_from_file put a module attribute
      query_ast =
        quote do
          defmodule GqlFromFileInvalid do
            use GraphqlQuery

            def query do
              document_with_options ignore: true do
                gql_from_file("test/fixtures/invalid_query.graphql", ignore: false)
              end
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.eval_quoted(query_ast)
        end)

      # Should have warnings because ignore: false overrides ignore: true
      assert logs =~ "unused variable"

      call_ast =
        quote do
          GqlFromFileInvalid.query()
        end

      {query, logs} =
        ExUnit.CaptureIO.with_io(fn ->
          {query, _} = Code.eval_quoted(call_ast)
          query
        end)

      assert %Document{query: result, type: :query} = query
      assert result =~ "query InvalidQuery($unused: String"
      assert logs == ""
    end

    test "gql_from_file inherits runtime option" do
      ast =
        quote do
          defmodule TestGqlFromFileRuntime do
            import GraphqlQuery

            def query do
              document_with_options runtime: true do
                gql_from_file("test/fixtures/invalid_query.graphql")
              end
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.eval_quoted(ast)
        end)

      assert logs == ""

      runtime_ast =
        quote do
          TestGqlFromFileRuntime.query()
        end

      {query, logs} =
        ExUnit.CaptureLog.with_log(fn ->
          {query, _} = Code.eval_quoted(runtime_ast)
          query
        end)

      # Now we have warning logs because it was checked on runtime
      assert logs =~ "unused variable"
      assert %Document{query: result, type: :query} = query
      assert result =~ "query InvalidQuery($unused: String"
    end

    test "multiple gql_from_file calls with different types" do
      results =
        document_with_options ignore: true do
          {
            gql_from_file("test/fixtures/test_query.graphql"),
            gql_from_file("test/fixtures/test_fragment.graphql", type: :fragment)
          }
        end

      assert {%Document{type: :query}, %Fragment{}} = results
    end

    test "mixed macro calls in document_with_options" do
      results =
        document_with_options ignore: true do
          %{
            sigil: ~GQL"{
  user {
    id
  }
}
",
            gql_macro: gql("query { posts { title } }"),
            from_file: gql_from_file("test/fixtures/test_query.graphql")
          }
        end

      assert %{
               sigil: %Document{type: :query},
               gql_macro: %Document{type: :query},
               from_file: %Document{type: :query}
             } = results
    end

    test "nested document_with_options blocks" do
      result =
        document_with_options ignore: true do
          document_with_options type: :fragment do
            gql """
            fragment UserData on User {
              id
              name
            }
            """
          end
        end

      # Inner options should take precedence
      assert %Fragment{} = result
    end

    test "document_with_options with fragments option" do
      _fragment =
        document_with_options type: :fragment do
          ~GQL"""
          fragment TestFragment on User {
            id
            email
          }
          """f
        end

      # Note: This test focuses on the document_with_options functionality
      # The fragment integration would require more complex setup
      query =
        document_with_options ignore: true do
          ~GQL"""
          query GetUserWithFragment {
            user {
              ...TestFragment
            }
          }
          """
        end

      assert %Document{type: :query} = query
    end

    test "document_with_options with evaluate option" do
      defmodule TestGqlEvaluate3 do
        import GraphqlQuery

        defmodule TestEvaluateHelper do
          def get_user_fields, do: "id name email"
        end

        def query do
          document_with_options evaluate: true do
            gql """
            query GetUser {
              user {
            #{TestEvaluateHelper.get_user_fields()}
              }
            }
            """
          end
        end
      end

      assert %Document{query: result} = TestGqlEvaluate3.query()
      assert result =~ "id name email"
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

      sigil_document = ~GQL"""
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

      assert %Document{query: sigil_query, type: :query} = sigil_document

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

      sigil_document = ~GQL"""
      {
        user {
          id
          name
        }
      }
      """

      assert %Document{query: sigil_query, type: :query} = sigil_document
      assert sigil_query == query
    end
  end

  describe "gql macro" do
    test "warning for static queries" do
      data = ~s/
      defmodule TestGqlStatic do
        import GraphqlQuery
        def query do
          gql """
          query GetUser($id: ID!) {
            user(id: $id) {
              name
              email
            }
          }
          """
        end
      end
     /

      expected = """
      query GetUser($id: ID!) {
        user(id: $id) {
          name
          email
        }
      }
      """

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          [{compiled_module, _}] = Code.compile_string(data)
          assert %Document{query: result, type: :query} = compiled_module.query()
          assert result == expected
        end)

      assert logs =~ "warning"
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

      assert %Document{query: result, type: :query} = TestGqlAttributes.query_with_attributes()
      assert result =~ "query GetUser($id: ID!)"
      assert result =~ "id name email"
    end

    test "works with other GQL results in module attributes if evaluate" do
      defmodule TestGqlWithFragments do
        import GraphqlQuery

        @user_fragment ~GQL"""
        fragment UserFields on User {
          name
          email
        }
        """f

        def query_with_fragment do
          # Need evaluation to expand fragments
          gql [evaluate: true], """
          query {
            user {
              ...UserFields
            }
          }
          #{@user_fragment}
          """
        end
      end

      assert %Document{query: result, type: :query} = TestGqlWithFragments.query_with_fragment()
      assert result =~ "query {"
      assert result =~ "...UserFields"
      assert result =~ "fragment UserFields on User"
    end

    test "no need to evaluate if fragments are explicitly used" do
      defmodule TestGqlWithFragmentsOptions do
        import GraphqlQuery

        @user_fragment ~GQL"""
        fragment UserFields on User {
          name
          email
        }
        """f

        def query_with_fragment do
          # Need evaluation to expand fragments
          gql [fragments: [@user_fragment]], """
          query {
            user {
              ...UserFields
            }
          }
          """
        end
      end

      document = TestGqlWithFragmentsOptions.query_with_fragment()
      assert %Document{query: result, type: :query} = document

      assert result =~ "query {"
      assert result =~ "...UserFields"
      # In normal query the fragment is not expanded
      refute result =~ "fragment UserFields on User"

      # But when transformed to string, it should include the fragment definition
      assert to_string(document) =~ "fragment UserFields on User"
    end

    test "works with evaluate option and module calls" do
      defmodule TestGqlEvaluate4 do
        import GraphqlQuery

        defmodule Helper do
          def fragment_name, do: "UserIdentifier"

          def fragment do
            ~GQL"""
            fragment UserIdentifier on User {
              id
              email
            }
            """f
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

      assert %Document{query: result, type: :query} = TestGqlEvaluate4.query_with_evaluate()
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
      assert %Document{query: result, type: :query} = TestGqlLocalVars.query_with_local_vars()
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
      assert %Document{query: result, type: :query} =
               TestGqlRuntime.query_with_runtime_validation("$id")

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
      assert %Document{query: result, type: :query} = TestGqlIgnore.query_with_ignore_option()
      assert result =~ "query {"
      assert result =~ "id\nname"
    end

    test "ignore option suppresses warnings" do
      module =
        quote do
          defmodule TestGqlIgnoreWarnings do
            import GraphqlQuery

            defmodule Helper do
              def some_field, do: "name"
            end

            def query_with_ignore do
              gql [ignore: true], "query { #{Helper.some_field()} }"
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_quoted(module)
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

      assert %Document{query: result, type: :query} =
               TestGqlModuleOptions.query_with_module_options()

      assert result =~ "query {"
      assert result =~ "id name"
    end

    test "validates and warns about invalid GraphQL in gql macro" do
      ast =
        quote do
          defmodule TestGqlValidationUnusedField do
            import GraphqlQuery

            @fields "id name"

            def invalid_query do
              gql """
              query GetUser($unused: String) {
                user {
                  #{@fields}
                }
              }
              """
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_quoted(ast)
        end)

      assert logs =~ "warning"
      assert logs =~ "unused variable"
    end
  end

  describe "compile warnings" do
    test "compile warning" do
      ast =
        quote do
          import GraphqlQuery
          ~GQL"{}"
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_quoted(ast)
        end)

      assert logs =~ "warning"
      assert logs =~ "Validation errors"
      assert logs =~ "syntax error: expected at least one Selection in Selection Set"
    end
  end
end
