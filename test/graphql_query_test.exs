defmodule GraphqlQueryTest do
  use ExUnit.Case
  import GraphqlQuery
  doctest GraphqlQuery

  import ExUnit.CaptureLog

  alias GraphqlQuery.{Document, Fragment}

  describe "document_with_options/2" do
    test "should not warn on schema errors when they are ignored on schema" do
      ast =
        quote do
          import GraphqlQuery

          document_with_options schema: Test.ErrorSchema do
            ~GQL"""
            query GetUser($id: ID!) {
              user(id: $id) {
                email
              }
            }
            """
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_quoted(ast)
        end)

      assert logs == ""
    end

    test "deprecated field usage emits a compile-time warning" do
      ast =
        quote do
          import GraphqlQuery

          document_with_options schema: Test.Schema do
            ~GQL"""
            query GetUser($id: ID!) {
              user(id: $id) {
                name
                oldName
                email
                oldEmail
              }
            }
            """
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_quoted(ast)
        end)

      assert logs =~ "Field 'oldEmail' on type 'User' is deprecated: Use 'email' field instead"
      assert logs =~ "Field 'oldName' on type 'User' is deprecated"
      refute logs =~ "Field 'oldName' on type 'User' is deprecated: "
    end

    test "no warning when no deprecated fields are used" do
      ast =
        quote do
          import GraphqlQuery

          document_with_options schema: Test.Schema do
            ~GQL"""
            query GetUser($id: ID!) {
              user(id: $id) {
                email
              }
            }
            """
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_quoted(ast)
        end)

      assert logs == ""
    end

    test "no deprecation warning when no schema is provided" do
      ast =
        quote do
          import GraphqlQuery

          ~GQL"""
          query GetUser($id: ID!) {
            user(id: $id) {
              oldEmail
            }
          }
          """i
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_quoted(ast)
        end)

      assert logs == ""
    end

    test "deprecated field in fragment emits a compile-time warning" do
      ast =
        quote do
          import GraphqlQuery

          document_with_options schema: Test.Schema do
            ~GQL"""
            fragment UserFields on User {
              email
              oldEmail
            }
            """f
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_quoted(ast)
        end)

      assert logs =~ "Field 'oldEmail' on type 'User' is deprecated: Use 'email' field instead"
    end

    test "deprecated field usage emits a runtime warning" do
      logs =
        capture_log(fn ->
          document_with_options schema: Test.Schema, runtime: true do
            ~GQL"""
            query GetUser($id: ID!) {
              user(id: $id) {
                email
                oldEmail
              }
            }
            """
          end
        end)

      assert logs =~ "Field 'oldEmail' on type 'User' is deprecated: Use 'email' field instead"
    end

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
      # but it should on runtime
      logs =
        capture_log(fn ->
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
        end)

      assert logs =~ "[GraphqlQuery] Runtime Validation error"
      assert logs =~ "cannot find fragment `NonExistentFragment` in this document"
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

    test "static runtime don't warn on compile time even if other opts can't be resolved" do
      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          query_ast =
            quote do
              defmodule TestGqlRuntimeWithUnresolvableOpts do
                import GraphqlQuery

                def test(ignore) do
                  gql [ignore: ignore, runtime: true], """
                  query GetUser {
                    user {
                      id
                    }
                  }
                  """
                end
              end

              TestGqlRuntimeWithUnresolvableOpts.test(false)
            end

          {query, _} = Code.eval_quoted(query_ast)

          assert %Document{} = query
        end)

      assert logs == ""
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

      test_path = __ENV__.file
      assert %Document{query: result, type: :query, path: ^test_path} = TestGqlEvaluate2.query()
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

    test "sigil 'c' option forces compile-time validation even with runtime option" do
      ast =
        quote do
          defmodule TestCompileTimeForced do
            use GraphqlQuery, runtime: true

            def query_with_c_option do
              ~GQL"{}"c
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_quoted(ast)
        end)

      # Should have compile-time warnings despite runtime: true being set at module level
      assert logs =~ "warning"
      assert logs =~ "Validation errors"
      assert logs =~ "syntax error: expected at least one Selection in Selection Set"
    end
  end

  describe "unresolvable options - runtime fallback" do
    test "gql macro - internal function call in options should warn" do
      query_ast =
        quote do
          defmodule TestUnresolvableFunction do
            import GraphqlQuery

            defp schema do
              Test.Schema
            end

            def query do
              gql [schema: schema()], "query { user { id name unknown } }"
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.eval_quoted(query_ast)
        end)

      assert logs =~ "[GraphqlQuery] Can't extract options on compile time" or
               logs =~ "Falling back to runtime validation"

      call_ast =
        quote do
          TestUnresolvableFunction.query()
        end

      {query, logs} =
        with_log(fn ->
          {query, _} = Code.eval_quoted(call_ast)
          query
        end)

      assert %Document{query: result, type: :query} = query
      assert result == "query { user { id name unknown } }"
      assert logs =~ "type `User` does not have a field `unknown`"
    end

    test "gql macro - variable as options should warn" do
      query_ast =
        quote do
          defmodule TestUnresolvableVariable do
            import GraphqlQuery

            def query do
              opts = [schema: Test.Schema]
              gql opts, "query { user { id name unknown } }"
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.eval_quoted(query_ast)
        end)

      assert logs =~ "[GraphqlQuery] Can't extract options on compile time" or
               logs =~ "Falling back to runtime validation"

      call_ast =
        quote do
          TestUnresolvableVariable.query()
        end

      {query, logs} =
        with_log(fn ->
          {query, _} = Code.eval_quoted(call_ast)
          query
        end)

      assert %Document{query: result, type: :query} = query
      assert result == "query { user { id name unknown } }"
      assert logs =~ "type `User` does not have a field `unknown`"
    end

    test "gql macro - function accessing variables should warn" do
      query_ast =
        quote do
          defmodule TestFunctionWithVariables do
            import GraphqlQuery

            def query do
              schema = Test.Schema
              gql [schema: schema], "query { user { id name unknown } }"
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.eval_quoted(query_ast)
        end)

      assert logs =~
               "[GraphqlQuery] Can't extract the value for the option \"schema\" on compile time."

      assert logs =~ "Falling back to runtime validation"

      call_ast =
        quote do
          TestFunctionWithVariables.query()
        end

      {query, logs} =
        with_log(fn ->
          {query, _} = Code.eval_quoted(call_ast)
          query
        end)

      assert %Document{query: result, type: :query} = query
      assert result == "query { user { id name unknown } }"
      assert logs =~ "type `User` does not have a field `unknown`"
    end

    test "gql macro with invalid fragment option should warn" do
      query_ast =
        quote do
          defmodule TestFragmentsUnresolvable do
            import GraphqlQuery

            defp get_fragments do
              "not a valid fragments list"
            end

            def query do
              gql [fragments: get_fragments()], "query { user { id } }"
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.eval_quoted(query_ast)
        end)

      assert logs =~ "Can't extract options on compile time" or
               logs =~ "Falling back to runtime validation"
    end

    test "gql_from_file expand until string" do
      query_ast =
        quote do
          defmodule TestGqlFromFileExpandString do
            import GraphqlQuery

            @base_path "test/fixtures"

            def query do
              gql_from_file "#{@base_path}/test_query.graphql"
            end
          end
        end

      Code.eval_quoted(query_ast)

      call_ast =
        quote do
          TestGqlFromFileExpandString.query()
        end

      {query, _} = Code.eval_quoted(call_ast)

      assert %Document{query: result, type: :query} = query
      assert result =~ "query GetUser($id: ID!)"
    end

    test "gql_from_file with base directory from public method in other module" do
      query_ast =
        quote do
          defmodule PathProvider do
            def get_base_path, do: "test/fixtures"
          end

          defmodule TestGqlFromFilePublicMethod do
            import GraphqlQuery

            def query do
              gql_from_file "#{PathProvider.get_base_path()}/test_query.graphql"
            end
          end
        end

      Code.eval_quoted(query_ast)

      call_ast =
        quote do
          TestGqlFromFilePublicMethod.query()
        end

      {query, _} = Code.eval_quoted(call_ast)

      assert %Document{query: result, type: :query} = query
      assert result =~ "query GetUser($id: ID!)"
    end

    test "gql_from_file with call to internal method - should fail at compile time" do
      query_ast =
        quote do
          defmodule TestGqlFromFileInternalMethod do
            import GraphqlQuery

            defp get_filename, do: "test_query.graphql"

            def query do
              gql_from_file("test/fixtures/#{get_filename()}")
            end
          end
        end

      # This should fail at compile time because function calls in interpolation can't be expanded
      assert_raise ArgumentError, ~r/The file path for gql_from_file\/2 must be a string/, fn ->
        Code.eval_quoted(query_ast)
      end
    end

    test "gql_from_file with nested interpolation and module attributes" do
      query_ast =
        quote do
          defmodule TestGqlFromFileNestedExpansion do
            import GraphqlQuery

            @base "test"
            @subdir "fixtures"

            def query do
              gql_from_file "#{@base}/#{@subdir}/test_query.graphql"
            end
          end
        end

      Code.eval_quoted(query_ast)

      call_ast =
        quote do
          TestGqlFromFileNestedExpansion.query()
        end

      {query, _} = Code.eval_quoted(call_ast)

      assert %Document{query: result, type: :query} = query
      assert result =~ "query GetUser($id: ID!)"
    end

    test "gql_from_file incorrect expansion - nonexistent file fails at compile time" do
      query_ast =
        quote do
          defmodule TestGqlFromFileIncorrectExpansion do
            import GraphqlQuery

            @base_path "test/fixtures"

            def query do
              gql_from_file("#{@base_path}/nonexistent_file.graphql")
            end
          end
        end

      # This should fail at compile time because the file doesn't exist
      assert_raise File.Error,
                   ~r/could not read \"test\/fixtures\/nonexistent_file.graphql\": no such file or directory/,
                   fn ->
                     Code.eval_quoted(query_ast)
                   end
    end

    test "gql_from_file with runtime resolution using document_with_options" do
      query_ast =
        quote do
          defmodule TestGqlFromFileRuntimeResolution do
            import GraphqlQuery

            @filename "test/fixtures/test_query.graphql"

            def query do
              document_with_options runtime: true do
                gql_from_file("#{@filename}")
              end
            end
          end
        end

      Code.eval_quoted(query_ast)

      call_ast =
        quote do
          TestGqlFromFileRuntimeResolution.query()
        end

      {query, _} = Code.eval_quoted(call_ast)

      assert %Document{query: result, type: :query} = query
      assert result =~ "query GetUser($id: ID!)"
    end

    test "gql_from_file macro - function call in options should warn" do
      content = "query { user { id name unknown } }"

      with_tmp_file(content, fn file_path ->
        query_ast =
          quote do
            defmodule TestGqlFromFileUnresolvable do
              import GraphqlQuery

              defp get_schema_dynamically do
                Test.Schema
              end

              def query do
                gql_from_file(unquote(file_path), schema: get_schema_dynamically())
              end
            end
          end

        logs =
          ExUnit.CaptureIO.capture_io(:stderr, fn ->
            Code.eval_quoted(query_ast)
          end)

        assert logs =~ "Can't extract options on compile time" or
                 logs =~ "Falling back to runtime validation"

        call_ast =
          quote do
            TestGqlFromFileUnresolvable.query()
          end

        {query, logs} =
          with_log(fn ->
            {query, _} = Code.eval_quoted(call_ast)
            query
          end)

        assert %Document{query: result, type: :query} = query
        assert result == content
        assert logs =~ "type `User` does not have a field `unknown`"
      end)
    end

    test "gql_from_file macro - specific opt in options should warn" do
      content = "query { user { id name unknown } }"

      with_tmp_file(content, fn file_path ->
        query_ast =
          quote do
            defmodule TestGqlFromFileUnresolvable do
              import GraphqlQuery

              def query do
                schema = Test.Schema
                gql_from_file(unquote(file_path), schema: schema)
              end
            end
          end

        logs =
          ExUnit.CaptureIO.capture_io(:stderr, fn ->
            Code.eval_quoted(query_ast)
          end)

        assert logs =~
                 "[GraphqlQuery] Can't extract the value for the option \"schema\" on compile time."

        assert logs =~ "Falling back to runtime validation"

        call_ast =
          quote do
            TestGqlFromFileUnresolvable.query()
          end

        {query, logs} =
          with_log(fn ->
            {query, _} = Code.eval_quoted(call_ast)
            query
          end)

        assert %Document{query: result, type: :query} = query
        assert result == content
        assert logs =~ "type `User` does not have a field `unknown`"
      end)
    end

    test "gql_from_file macro - function with variables should warn" do
      content = "query { user { id name unknown } }"

      with_tmp_file(content, fn file_path ->
        query_ast =
          quote do
            defmodule TestGqlFromFileVars do
              import GraphqlQuery

              def query do
                opts = [schema: Test.Schema]
                gql_from_file(unquote(file_path), opts)
              end
            end
          end

        logs =
          ExUnit.CaptureIO.capture_io(:stderr, fn ->
            Code.eval_quoted(query_ast)
          end)

        assert logs =~ "Can't extract options on compile time"
        assert logs =~ "Falling back to runtime validation"

        call_ast =
          quote do
            TestGqlFromFileVars.query()
          end

        {query, logs} =
          with_log(fn ->
            {query, _} = Code.eval_quoted(call_ast)
            query
          end)

        assert %Document{query: result, type: :query} = query
        assert result == content
        assert logs =~ "type `User` does not have a field `unknown`"
      end)
    end

    test "document_with_options - function call in options should warn" do
      query_ast =
        quote do
          defmodule TestDocumentWithUnresolvable do
            import GraphqlQuery

            defp schema do
              Test.Schema
            end

            def query do
              document_with_options schema: schema() do
                ~GQL"{
  user {
    id
    name
    unknown
  }
}
"
              end
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.eval_quoted(query_ast)
        end)

      assert logs =~ "Can't extract the value for the option \"schema\" on compile time"
      assert logs =~ "Falling back to runtime validation"

      call_ast =
        quote do
          TestDocumentWithUnresolvable.query()
        end

      {query, logs} =
        with_log(fn ->
          {query, _} = Code.eval_quoted(call_ast)
          query
        end)

      assert %Document{query: result, type: :query} = query
      assert result == "{\n  user {\n    id\n    name\n    unknown\n  }\n}\n"
      assert logs =~ "type `User` does not have a field `unknown`"
    end

    test "document_with_options - function accessing variables should warn" do
      query_ast =
        quote do
          defmodule TestDocumentWithVars do
            import GraphqlQuery

            def query do
              opts = [schema: Test.Schema]

              document_with_options opts do
                ~GQL"""
                {
                  user {
                    id
                    name
                    unknown
                  }
                }
                """
              end
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.eval_quoted(query_ast)
        end)

      assert logs =~ "Can't extract options on compile time"
      assert logs =~ "Falling back to runtime validation"

      call_ast =
        quote do
          TestDocumentWithVars.query()
        end

      {query, logs} =
        with_log(fn ->
          {query, _} = Code.eval_quoted(call_ast)
          query
        end)

      assert %Document{query: result, type: :query} = query
      assert result == "{\n  user {\n    id\n    name\n    unknown\n  }\n}\n"
      assert logs =~ "type `User` does not have a field `unknown`"
    end

    test "warning messages contain documentation links" do
      query_ast =
        quote do
          defmodule TestDocumentationLinks do
            import GraphqlQuery

            def query do
              opts = [schema: Test.Schema]
              gql opts, "query { user { id } }"
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.eval_quoted(query_ast)
        end)

      assert logs =~ "If you want to learn more about what is allowed in Elixir Macros"
      assert logs =~ "following documentation https://hexdocs.pm/graphql_query/macros.html"
    end

    test "basic unresolvable case with invalid fragment type" do
      query_ast =
        quote do
          defmodule TestInvalidFragments2 do
            import GraphqlQuery

            @invalid_fragments ~GQL"""
            fragment Test on User {
              name
            }
            """i

            def query do
              gql [fragments: [@invalid_fragments]], "query { user { id } }"
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.eval_quoted(query_ast)
        end)

      # Should warn about invalid fragments
      assert logs =~ "Fragment in @invalid_fragments evaluated as %GraphqlQuery.Document{}"
      assert logs =~ "Falling back to runtime validation"
    end

    test "document_with_options with invalid fragment type" do
      query_ast =
        quote do
          defmodule TestInvalidFragments do
            import GraphqlQuery

            @invalid_fragments ~GQL"""
            fragment Test on User {
              name
            }
            """i

            def query do
              document_with_options fragments: [@invalid_fragments] do
                ~GQL"""
                {
                  user {
                    id
                  }
                }
                """
              end
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.eval_quoted(query_ast)
        end)

      # Should warn about invalid fragments
      assert logs =~ "Fragment in @invalid_fragments evaluated as %GraphqlQuery.Document{}"
      assert logs =~ "Falling back to runtime validation."
    end
  end

  describe "global ignore option" do
    test "global ignore suppresses compile-time warnings in gql macro" do
      ast =
        quote do
          defmodule TestGlobalIgnoreGql do
            use GraphqlQuery, ignore: true

            def query_with_unused_var do
              gql """
              query GetUser($unused: String) {
                user {
                  id
                  name
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

      # Should not have validation warnings due to global ignore
      refute logs =~ "unused variable"
      refute logs =~ "[GraphqlQuery]"

      # But the query should still be resolved correctly at runtime
      call_ast =
        quote do
          TestGlobalIgnoreGql.query_with_unused_var()
        end

      {query, _} = Code.eval_quoted(call_ast)
      assert %Document{query: result} = query
      assert result =~ "query GetUser($unused: String)"
      assert result =~ "user {"
      assert result =~ "id"
      assert result =~ "name"
    end

    test "global ignore suppresses compile-time warnings in gql_from_file macro" do
      content = """
      query GetUser($unused: String) {
        user {
          id
          name
        }
      }
      """

      with_tmp_file(content, fn file_path ->
        ast =
          quote do
            defmodule TestGlobalIgnoreGqlFromFile do
              use GraphqlQuery, ignore: true

              def query_from_file do
                gql_from_file(unquote(file_path))
              end
            end
          end

        logs =
          ExUnit.CaptureIO.capture_io(:stderr, fn ->
            Code.compile_quoted(ast)
          end)

        # Should not have validation warnings due to global ignore
        refute logs =~ "unused variable"
        refute logs =~ "[GraphqlQuery]"

        # But the query should still be resolved correctly
        call_ast =
          quote do
            TestGlobalIgnoreGqlFromFile.query_from_file()
          end

        {query, _} = Code.eval_quoted(call_ast)
        assert %Document{query: result} = query
        assert result =~ "query GetUser($unused: String)"
        assert result =~ "user {"
        assert result =~ "id"
        assert result =~ "name"
      end)
    end

    test "global ignore suppresses compile-time warnings in ~GQL sigil" do
      ast =
        quote do
          defmodule TestGlobalIgnoreSigil do
            use GraphqlQuery, ignore: true

            def query_with_unused_var do
              ~GQL"""
              query GetUser($unused: String) {
                user {
                  id
                  name
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

      # Should not have validation warnings due to global ignore
      refute logs =~ "unused variable"
      refute logs =~ "[GraphqlQuery]"

      # But the query should still be resolved correctly
      call_ast =
        quote do
          TestGlobalIgnoreSigil.query_with_unused_var()
        end

      {query, _} = Code.eval_quoted(call_ast)
      assert %Document{query: result} = query
      assert result =~ "query GetUser($unused: String)"
      assert result =~ "user {"
      assert result =~ "id"
      assert result =~ "name"
    end

    test "global ignore works with document_with_options" do
      ast =
        quote do
          defmodule TestGlobalIgnoreDocumentWithOptions do
            use GraphqlQuery, ignore: true

            def query_with_document_options do
              document_with_options type: :query do
                gql """
                query GetUser($unused: String) {
                  user {
                    id
                    name
                  }
                }
                """
              end
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_quoted(ast)
        end)

      # Should not have validation warnings due to global ignore
      refute logs =~ "unused variable"
      refute logs =~ "[GraphqlQuery]"

      # Query should still work correctly
      call_ast =
        quote do
          TestGlobalIgnoreDocumentWithOptions.query_with_document_options()
        end

      {query, _} = Code.eval_quoted(call_ast)
      assert %Document{query: result} = query
      assert result =~ "query GetUser($unused: String)"
      assert result =~ "user {"
      assert result =~ "id"
      assert result =~ "name"
    end

    test "local options if they can be read take precedence over global ignore" do
      ast =
        quote do
          defmodule TestGlobalIgnorePrecedence do
            use GraphqlQuery, ignore: true

            def query_with_local_options do
              gql [ignore: false], """
              query GetUser($unused: String) {
                user {
                  id
                  name
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

      # Global ignore should take precedence, so no validation warnings
      assert logs =~ "unused variable"
    end
  end

  describe "global runtime option" do
    test "global runtime defers validation to runtime in gql macro" do
      ast =
        quote do
          defmodule TestGlobalRuntimeGql do
            use GraphqlQuery, runtime: true

            def query_with_unused_var do
              gql """
              query GetUser($unused: String) {
                user {
                  id
                  name
                  unknown_field
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

      # Should not have compile-time warnings due to global runtime
      refute logs =~ "unused variable"
      refute logs =~ "unknown_field"
      refute logs =~ "[GraphqlQuery]"

      # But runtime validation should catch the errors
      call_ast =
        quote do
          TestGlobalRuntimeGql.query_with_unused_var()
        end

      {query, logs} =
        ExUnit.CaptureLog.with_log(fn ->
          {query, _} = Code.eval_quoted(call_ast)
          query
        end)

      # Should have runtime validation warnings
      assert logs =~ "unused variable"
      # Note: unknown_field warnings would require a schema to be configured

      assert %Document{query: result} = query
      assert result =~ "query GetUser($unused: String)"
      assert result =~ "unknown_field"
    end

    test "global runtime defers validation to runtime in gql_from_file macro" do
      content = """
      query GetUser($unused: String) {
        user {
          id
          name
          unknown_field
        }
      }
      """

      with_tmp_file(content, fn file_path ->
        ast =
          quote do
            defmodule TestGlobalRuntimeGqlFromFile do
              use GraphqlQuery, runtime: true

              def query_from_file do
                gql_from_file(unquote(file_path))
              end
            end
          end

        logs =
          ExUnit.CaptureIO.capture_io(:stderr, fn ->
            Code.compile_quoted(ast)
          end)

        # Should not have compile-time warnings due to global runtime
        refute logs =~ "unused variable"
        refute logs =~ "unknown_field"
        refute logs =~ "[GraphqlQuery]"

        # We delete the file, to make sure it's not read more than once
        File.rm(file_path)

        # But runtime validation should catch the errors
        call_ast =
          quote do
            TestGlobalRuntimeGqlFromFile.query_from_file()
          end

        {query, logs} =
          with_log(fn ->
            {query, _} = Code.eval_quoted(call_ast)
            query
          end)

        # Should have runtime validation warnings
        assert logs =~ "unused variable"

        assert %Document{query: result} = query
        assert result =~ "query GetUser($unused: String)"
        assert result =~ "unknown_field"
      end)
    end

    test "global runtime defers validation to runtime in ~GQL sigil" do
      ast =
        quote do
          defmodule TestGlobalRuntimeSigil do
            use GraphqlQuery, runtime: true

            def query_with_unused_var do
              ~GQL"""
              query GetUser($unused: String) {
                user {
                  id
                  name
                  unknown_field
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

      # Should not have compile-time warnings due to global runtime
      refute logs =~ "unused variable"
      refute logs =~ "unknown_field"
      refute logs =~ "[GraphqlQuery]"

      # But runtime validation should catch the errors
      call_ast =
        quote do
          TestGlobalRuntimeSigil.query_with_unused_var()
        end

      {query, logs} =
        ExUnit.CaptureLog.with_log(fn ->
          {query, _} = Code.eval_quoted(call_ast)
          query
        end)

      # Should have runtime validation warnings
      assert logs =~ "unused variable"

      assert %Document{query: result} = query
      assert result =~ "query GetUser($unused: String)"
      assert result =~ "unknown_field"
    end

    test "global runtime works with document_with_options" do
      ast =
        quote do
          defmodule TestGlobalRuntimeDocumentWithOptions do
            use GraphqlQuery, runtime: true

            def query_with_document_options do
              document_with_options type: :query do
                gql """
                query GetUser($unused: String) {
                  user {
                    id
                    name
                    unknown_field
                  }
                }
                """
              end
            end
          end
        end

      logs =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_quoted(ast)
        end)

      # Should not have compile-time warnings due to global runtime
      refute logs =~ "unused variable"
      refute logs =~ "unknown_field"
      refute logs =~ "[GraphqlQuery]"

      # But runtime validation should catch the errors
      call_ast =
        quote do
          TestGlobalRuntimeDocumentWithOptions.query_with_document_options()
        end

      {query, logs} =
        ExUnit.CaptureLog.with_log(fn ->
          {query, _} = Code.eval_quoted(call_ast)
          query
        end)

      # Should have runtime validation warnings
      assert logs =~ "unused variable"

      assert %Document{query: result} = query
      assert result =~ "query GetUser($unused: String)"
      assert result =~ "unknown_field"
    end

    test "if local options can be read, takes preference over global options" do
      ast =
        quote do
          defmodule TestGlobalRuntimePrecedence do
            use GraphqlQuery, runtime: true

            def query_with_local_options do
              gql [runtime: false], """
              query GetUser($unused: String) {
                user {
                  id
                  name
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

      # Global runtime should take precedence, so no compile-time validation warnings
      assert logs =~ "unused variable"
      assert logs =~ "[GraphqlQuery]"

      # But runtime validation should still occur
      call_ast =
        quote do
          TestGlobalRuntimePrecedence.query_with_local_options()
        end

      {query, logs} =
        ExUnit.CaptureLog.with_log(fn ->
          {query, _} = Code.eval_quoted(call_ast)
          query
        end)

      # Should have runtime validation warnings
      refute logs =~ "unused variable"
      assert %Document{query: result} = query
      assert result =~ "query GetUser($unused: String)"
    end
  end

  describe "format option" do
    test "document_with_options with format: true applies formatting" do
      query =
        document_with_options format: true, ignore: true do
          gql """
          query GetUser($id: ID!) {
            user(id: $id) {
              id name
            }
          }
          """
        end

      result = to_string(query)

      # Should be formatted with proper indentation
      assert result =~ "query GetUser($id: ID!) {\n  user(id: $id) {\n    id\n    name\n  }\n}"
      assert %Document{format: true} = query
    end

    test "document_with_options with format: false preserves original formatting" do
      query =
        document_with_options format: false, ignore: true do
          gql """
          query GetUser($id: ID!) {
            user(id: $id) {
              id name
            }
          }
          """
        end

      result = to_string(query)

      assert result =~ "query GetUser($id: ID!) {\n  user(id: $id) {\n    id name\n  }\n}"
      assert %Document{format: false} = query
    end

    test "gql macro with format: true applies formatting" do
      query =
        gql [format: true, ignore: true], """
        query GetUser($id: ID!) {
        user(id: $id) {
        id
        name
        }
        }
        """

      result = to_string(query)

      # Should be formatted
      assert result =~ "query GetUser($id: ID!) {\n  user(id: $id) {\n    id\n    name\n  }\n}"
      assert %Document{format: true} = query
    end

    test "gql macro with format: false preserves original formatting" do
      query =
        gql [format: false, ignore: true], """
        query GetUser($id: ID!) {
        user(id: $id) {
        id name
        }
        }
        """

      result = to_string(query)

      # Should preserve original formatting (leading whitespace is normalized by gql macro)
      assert result =~ "query GetUser($id: ID!) {\nuser(id: $id) {\nid name\n}\n}"
      assert %Document{format: false} = query
    end

    test "fragment with format: true applies formatting" do
      fragment =
        document_with_options format: true, ignore: true do
          gql [type: :fragment], """
          fragment UserFields on User {
            id name email
          }
          """
        end

      result = to_string(fragment)

      # Should be formatted
      assert result =~ "fragment UserFields on User {\n  id\n  name\n  email\n}"
      assert %Fragment{format: true} = fragment
    end

    test "fragment with format: false preserves original formatting" do
      fragment =
        document_with_options format: false, ignore: true do
          gql [type: :fragment], """
          fragment UserFields on User {
            id name
            email
          }
          """
        end

      result = to_string(fragment)

      # Should preserve original formatting (now properly indented by mix format)
      assert result =~ "fragment UserFields on User {\n  id name\n  email\n}"
      assert %Fragment{format: false} = fragment
    end

    test "gql_from_file with runtime: true only reads the file once" do
      content = """
      query GetUser($id: ID!) {
        user(id: $id) {
          id
          name
        }
      }
      """

      with_tmp_file(content, fn file_path ->
        ast =
          quote do
            defmodule TestGqlFromFileRuntimeOnce do
              use GraphqlQuery, runtime: true

              def query_from_file do
                gql_from_file(unquote(file_path))
              end
            end
          end

        Code.compile_quoted(ast)

        # Delete the file to ensure it don't access again
        File.rm(file_path)
        refute File.exists?(file_path)

        call_ast =
          quote do
            TestGqlFromFileRuntimeOnce.query_from_file()
          end

        {query, _} = Code.eval_quoted(call_ast)

        assert %Document{query: result} = query
        assert result =~ "query GetUser($id: ID!)"

        {query, _} = Code.eval_quoted(call_ast)

        assert %Document{query: result} = query
        assert result =~ "query GetUser($id: ID!)"
      end)
    end

    test "gql_from_file with format: true applies formatting" do
      # Use existing test fixture
      query =
        document_with_options format: true do
          gql_from_file("test/fixtures/test_query.graphql")
        end

      result = to_string(query)

      # Should be formatted (the fixture content will be formatted)
      assert %Document{format: true} = query
      assert is_binary(result)
    end

    test "Document.new with format: true applies formatting" do
      query =
        GraphqlQuery.Document.new(
          """
          query GetUser($id: ID!) {
          user(id: $id) {
          id
          name
          }
          }
          """,
          format: true
        )

      result = to_string(query)

      # Should be formatted
      assert result =~ "query GetUser($id: ID!) {\n  user(id: $id) {\n    id\n    name\n  }\n}"
      assert %Document{format: true} = query
    end

    test "Fragment with format option via Document.new" do
      fragment =
        GraphqlQuery.Document.new(
          """
          fragment UserFields on User {
          id
          name
          email
          }
          """,
          type: :fragment,
          format: true
        )

      result = to_string(fragment)

      # Should be formatted
      assert result =~ "fragment UserFields on User {\n  id\n  name\n  email\n}"
      assert %Fragment{format: true} = fragment
    end

    test "format option defaults to false" do
      query = ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          id
          name
        }
      }
      """

      # Should have format: false by default
      assert %Document{format: false} = query

      # Should preserve original formatting (now properly indented by mix format)
      result = to_string(query)
      assert result =~ "query GetUser($id: ID!) {\n  user(id: $id) {\n    id\n    name\n  }\n}"
    end

    test "format option precedence - explicit option overrides document_with_options" do
      query =
        document_with_options format: true do
          gql [format: false, ignore: true], """
          query GetUser($id: ID!) {
          user(id: $id) {
          id
          name
          }
          }
          """
        end

      # Explicit format: false should override document_with_options format: true
      assert %Document{format: false} = query

      # Should preserve original formatting (leading whitespace is normalized by gql macro)
      result = to_string(query)
      assert result =~ "query GetUser($id: ID!) {\nuser(id: $id) {\nid\nname\n}\n}"
    end

    test "format works with complex queries including fragments" do
      fragment =
        GraphqlQuery.Document.new(
          """
          fragment UserFields on User {
          id
          name
          email
          }
          """,
          type: :fragment,
          format: true
        )

      query =
        GraphqlQuery.Document.new(
          """
          query GetUser($id: ID!) {
          user(id: $id) {
          ...UserFields
          }
          }
          """,
          fragments: [fragment],
          format: true
        )

      result = to_string(query)

      # Both query and fragment should be formatted
      expected_query = """
      query GetUser($id: ID!) {
        user(id: $id) {
          ...UserFields
        }
      }

      fragment UserFields on User {
        id
        name
        email
      }
      """

      # Remove trailing whitespace for comparison
      normalized_result = result |> String.trim()
      normalized_expected = expected_query |> String.trim()

      assert normalized_result == normalized_expected
    end

    test "module-level format option through MacroOptions" do
      # Test that MacroOptions includes format in validation
      {:ok, opts} = GraphqlQuery.MacroOptions.validate(format: true, ignore: false)
      assert opts.format == true
      assert opts.ignore == false

      # Test that format defaults to false
      {:ok, opts_default} = GraphqlQuery.MacroOptions.validate([])
      assert opts_default.format == false
    end
  end

  defp with_tmp_file(content, callback) do
    file_path = "test_#{abs(:erlang.unique_integer())}"
    File.write!(file_path, content)

    try do
      callback.(file_path)
    after
      if File.exists?(file_path), do: File.rm(file_path)
    end
  end
end
