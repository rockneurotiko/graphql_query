defmodule GraphqlQuery.Schema.Remote.HttpClientTest do
  use ExUnit.Case, async: true

  alias GraphqlQuery.Schema.Remote.HttpClient

  defmodule NoRetry do
    def build_request(req), do: Req.merge(req, retry: false)
  end

  describe "fetch/1" do
    test "returns error for non-existent host" do
      assert {:error, reason} =
               HttpClient.fetch("http://nonexistent.invalid.test/schema.graphql", NoRetry)

      assert is_binary(reason)
      assert reason =~ "Failed to fetch" or reason =~ "HTTP"
    end

    test "returns error for invalid URL" do
      assert {:error, reason} = HttpClient.fetch("not_a_url", NoRetry)
      assert is_binary(reason)
    end
  end

  describe "fetch/2 with schema module" do
    test "calls build_request/1 on the schema module" do
      # We test indirectly: define a module with build_request that adds a header
      # and verify fetch doesn't crash (the customization is applied)
      defmodule TestSchemaModuleForFetch do
        def build_request(req) do
          req
          |> Req.Request.put_header("x-test-header", "test-value")
          |> Req.merge(retry: false)
        end
      end

      # This will fail with a network error, but the build_request is called without error
      assert {:error, _reason} =
               HttpClient.fetch(
                 "http://nonexistent.invalid.test/schema.graphql",
                 TestSchemaModuleForFetch
               )
    end

    test "works with nil schema module (no customization)" do
      assert {:error, _reason} =
               HttpClient.fetch("http://nonexistent.invalid.test/schema.graphql", nil)
    end

    test "works with module that doesn't export build_request/1" do
      defmodule TestModuleNoBuildRequest do
        def some_other_function, do: :ok
      end

      assert {:error, _reason} =
               HttpClient.fetch(
                 "http://nonexistent.invalid.test/schema.graphql",
                 TestModuleNoBuildRequest
               )
    end
  end

  describe "introspect/2" do
    test "returns error for non-existent host" do
      assert {:error, reason} =
               HttpClient.introspect("http://nonexistent.invalid.test/graphql", NoRetry)

      assert is_binary(reason)
      assert reason =~ "introspect" or reason =~ "Failed"
    end

    test "returns error for invalid URL" do
      assert {:error, reason} = HttpClient.introspect("not_a_url", NoRetry)
      assert is_binary(reason)
    end

    test "calls build_request/1 on the schema module" do
      defmodule TestSchemaModuleForIntrospect do
        def build_request(req) do
          req
          |> Req.Request.put_header("x-test-header", "introspect-value")
          |> Req.merge(retry: false)
        end
      end

      # Will fail with network error, but build_request is called without error
      assert {:error, _reason} =
               HttpClient.introspect(
                 "http://nonexistent.invalid.test/graphql",
                 TestSchemaModuleForIntrospect
               )
    end
  end

  describe "fetch/2 with Req.Test stubs" do
    test "returns {:ok, body} on successful GET" do
      Req.Test.stub(:fetch_success, fn conn ->
        Req.Test.text(conn, "type Query { hello: String }")
      end)

      defmodule FetchSuccessSchema do
        def build_request(req), do: Req.merge(req, plug: {Req.Test, :fetch_success})
      end

      assert {:ok, "type Query { hello: String }"} =
               HttpClient.fetch("https://example.com/schema.graphql", FetchSuccessSchema)
    end

    test "returns {:error, _} on HTTP 4xx" do
      Req.Test.stub(:fetch_not_found, fn conn ->
        conn
        |> Plug.Conn.send_resp(404, "Not Found")
      end)

      defmodule FetchNotFoundSchema do
        def build_request(req),
          do: Req.merge(req, plug: {Req.Test, :fetch_not_found}, retry: false)
      end

      assert {:error, reason} =
               HttpClient.fetch("https://example.com/schema.graphql", FetchNotFoundSchema)

      assert reason =~ "HTTP 404"
    end

    test "returns {:error, _} on HTTP 5xx" do
      Req.Test.stub(:fetch_server_error, fn conn ->
        conn
        |> Plug.Conn.send_resp(500, "Internal Server Error")
      end)

      defmodule FetchServerErrorSchema do
        def build_request(req),
          do: Req.merge(req, plug: {Req.Test, :fetch_server_error}, retry: false)
      end

      assert {:error, reason} =
               HttpClient.fetch("https://example.com/schema.graphql", FetchServerErrorSchema)

      assert reason =~ "HTTP 500"
    end
  end

  describe "introspect/2 with Req.Test stubs" do
    test "returns {:ok, sdl} on successful introspection" do
      Req.Test.stub(:introspect_success, fn conn ->
        Req.Test.json(conn, %{
          "data" => %{
            "__schema" => %{
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
          }
        })
      end)

      defmodule IntrospectSuccessSchema do
        def build_request(req), do: Req.merge(req, plug: {Req.Test, :introspect_success})
      end

      assert {:ok, sdl} =
               HttpClient.introspect("https://example.com/graphql", IntrospectSuccessSchema)

      assert sdl =~ "type Query"
      assert sdl =~ "hello"
    end

    test "returns {:error, _} when introspection returns GraphQL errors" do
      Req.Test.stub(:introspect_gql_error, fn conn ->
        Req.Test.json(conn, %{
          "errors" => [
            %{"message" => "Not authorized to perform introspection"}
          ]
        })
      end)

      defmodule IntrospectGqlErrorSchema do
        def build_request(req),
          do: Req.merge(req, plug: {Req.Test, :introspect_gql_error}, retry: false)
      end

      assert {:error, reason} =
               HttpClient.introspect("https://example.com/graphql", IntrospectGqlErrorSchema)

      assert reason =~ "Not authorized to perform introspection"
    end

    test "returns {:error, _} on HTTP 401" do
      Req.Test.stub(:introspect_unauthorized, fn conn ->
        conn
        |> Plug.Conn.send_resp(401, "Unauthorized")
      end)

      defmodule IntrospectUnauthorizedSchema do
        def build_request(req),
          do: Req.merge(req, plug: {Req.Test, :introspect_unauthorized}, retry: false)
      end

      assert {:error, reason} =
               HttpClient.introspect("https://example.com/graphql", IntrospectUnauthorizedSchema)

      assert reason =~ "HTTP 401"
    end
  end
end
