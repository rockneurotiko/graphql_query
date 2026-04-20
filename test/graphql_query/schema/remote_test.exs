defmodule GraphqlQuery.Schema.RemoteTest do
  use ExUnit.Case, async: true

  alias GraphqlQuery.Schema.Remote

  describe "derive_schema_path/2" do
    test "converts simple module name to underscored path" do
      assert Remote.derive_schema_path(MyApp.Schema, "priv/schemas") ==
               "priv/schemas/my_app/schema.graphql"
    end

    test "converts nested module name to nested path" do
      assert Remote.derive_schema_path(MyApp.ExternalApi.Schema, "priv/graphql/schemas") ==
               "priv/graphql/schemas/my_app/external_api/schema.graphql"
    end

    test "converts CamelCase parts to underscored" do
      assert Remote.derive_schema_path(MyApp.ExternalSchema, "priv/schemas") ==
               "priv/schemas/my_app/external_schema.graphql"
    end

    test "handles single-part module name" do
      assert Remote.derive_schema_path(Schema, "priv/schemas") ==
               "priv/schemas/schema.graphql"
    end

    test "handles deeply nested module" do
      assert Remote.derive_schema_path(A.B.C.D.E, "dir") ==
               "dir/a/b/c/d/e.graphql"
    end

    test "works with different schemas directories" do
      assert Remote.derive_schema_path(MyApp.Schema, "custom/path") ==
               "custom/path/my_app/schema.graphql"
    end
  end

  describe "resolve_schemas_dir/1" do
    test "returns module option when provided as string" do
      assert Remote.resolve_schemas_dir("custom/path") == "custom/path"
    end

    test "returns default when nil and no app config" do
      # Clear any app config that might be set
      original = Application.get_env(:graphql_query, :schemas_dir)
      Application.delete_env(:graphql_query, :schemas_dir)

      try do
        assert Remote.resolve_schemas_dir(nil) == "priv/graphql/schemas"
      after
        if original, do: Application.put_env(:graphql_query, :schemas_dir, original)
      end
    end

    test "returns app config when nil and app config is set" do
      original = Application.get_env(:graphql_query, :schemas_dir)
      Application.put_env(:graphql_query, :schemas_dir, "configured/path")

      try do
        assert Remote.resolve_schemas_dir(nil) == "configured/path"
      after
        if original do
          Application.put_env(:graphql_query, :schemas_dir, original)
        else
          Application.delete_env(:graphql_query, :schemas_dir)
        end
      end
    end
  end

  describe "save_schema/2" do
    setup do
      tmp_dir = System.tmp_dir!() |> Path.join("gql_remote_test_#{:rand.uniform(100_000)}")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      %{tmp_dir: tmp_dir}
    end

    test "creates directories and writes file", %{tmp_dir: tmp_dir} do
      path = Path.join([tmp_dir, "nested", "dir", "schema.graphql"])
      content = "type Query { hello: String }"

      assert :ok = Remote.save_schema(path, content)
      assert File.read!(path) == content
    end

    test "overwrites existing file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "schema.graphql")
      File.mkdir_p!(tmp_dir)
      File.write!(path, "old content")

      assert :ok = Remote.save_schema(path, "new content")
      assert File.read!(path) == "new content"
    end
  end

  describe "schemas_match?/2" do
    setup do
      tmp_dir = System.tmp_dir!() |> Path.join("gql_match_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      %{tmp_dir: tmp_dir}
    end

    test "returns true when content matches", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "schema.graphql")
      content = "type Query { hello: String }"
      File.write!(path, content)

      assert Remote.schemas_match?(path, content)
    end

    test "returns false when content differs", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "schema.graphql")
      File.write!(path, "type Query { hello: String }")

      refute Remote.schemas_match?(path, "type Query { world: String }")
    end

    test "returns false when file doesn't exist", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "nonexistent.graphql")
      refute Remote.schemas_match?(path, "content")
    end

    test "handles empty content", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "empty.graphql")
      File.write!(path, "")

      assert Remote.schemas_match?(path, "")
      refute Remote.schemas_match?(path, "not empty")
    end
  end

  describe "default_schemas_dir/0" do
    test "returns the default path" do
      assert Remote.default_schemas_dir() == "priv/graphql/schemas"
    end
  end

  describe "resolve_url/1" do
    test "returns a plain string URL unchanged" do
      assert Remote.resolve_url("https://example.com/schema.graphql") ==
               "https://example.com/schema.graphql"
    end

    test "calls {Module, :fun} and returns its result" do
      defmodule UrlProvider do
        def url, do: "https://resolved.example.com/schema.graphql"
      end

      assert Remote.resolve_url({UrlProvider, :url}) ==
               "https://resolved.example.com/schema.graphql"
    end

    test "raises ArgumentError when {Module, :fun} returns a non-string" do
      defmodule BadUrlProvider do
        def url, do: 12_345
      end

      assert_raise ArgumentError, ~r/must return a non-empty string URL/, fn ->
        Remote.resolve_url({BadUrlProvider, :url})
      end
    end

    test "raises ArgumentError when {Module, :fun} returns an empty string" do
      defmodule EmptyUrlProvider do
        def url, do: ""
      end

      assert_raise ArgumentError, ~r/must return a non-empty string URL/, fn ->
        Remote.resolve_url({EmptyUrlProvider, :url})
      end
    end
  end

  defmodule NoRetry do
    def build_request(req), do: Req.merge(req, retry: false)
  end

  describe "fetch_schema/1" do
    setup do
      tmp_dir = System.tmp_dir!() |> Path.join("fetch_schema_test_#{:rand.uniform(100_000)}")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      %{tmp_dir: tmp_dir}
    end

    test "returns {:error, _} for :fetch mode when URL is unreachable", %{tmp_dir: tmp_dir} do
      info = %{
        module: NoRetry,
        remote: [url: "http://localhost:0/does_not_exist"],
        schema_path: Path.join(tmp_dir, "schema.graphql"),
        schemas_dir: tmp_dir
      }

      assert {:error, _reason} = Remote.fetch_schema(info)
    end

    test "returns {:error, _} for :introspect mode when URL is unreachable", %{tmp_dir: tmp_dir} do
      info = %{
        module: NoRetry,
        remote: [url: "http://localhost:0/graphql", mode: :introspect],
        schema_path: Path.join(tmp_dir, "schema.graphql"),
        schemas_dir: tmp_dir
      }

      assert {:error, _reason} = Remote.fetch_schema(info)
    end

    test "resolves {Module, :fun} URL before fetching", %{tmp_dir: tmp_dir} do
      defmodule FetchUrlProvider do
        def url, do: "http://localhost:0/schema.graphql"
      end

      info = %{
        module: NoRetry,
        remote: [url: {FetchUrlProvider, :url}],
        schema_path: Path.join(tmp_dir, "schema.graphql"),
        schemas_dir: tmp_dir
      }

      # The URL resolves fine but the endpoint is unreachable — confirms
      # resolve_url/1 is called and we get a network {:error, _}, not an ArgumentError.
      assert {:error, _reason} = Remote.fetch_schema(info)
    end

    test "returns {:ok, sdl} with :fetch mode via Req.Test stub", %{tmp_dir: tmp_dir} do
      Req.Test.stub(:remote_fetch_ok, fn conn ->
        Req.Test.text(conn, "type Query { users: [User] }")
      end)

      defmodule StubFetchModule do
        def build_request(req), do: Req.merge(req, plug: {Req.Test, :remote_fetch_ok})
      end

      info = %{
        module: StubFetchModule,
        remote: [url: "https://example.com/schema.graphql"],
        schema_path: Path.join(tmp_dir, "schema.graphql"),
        schemas_dir: tmp_dir
      }

      assert {:ok, "type Query { users: [User] }"} = Remote.fetch_schema(info)
    end

    test "returns {:ok, sdl} with :introspect mode via Req.Test stub", %{tmp_dir: tmp_dir} do
      Req.Test.stub(:remote_introspect_ok, fn conn ->
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

      defmodule StubIntrospectModule do
        def build_request(req), do: Req.merge(req, plug: {Req.Test, :remote_introspect_ok})
      end

      info = %{
        module: StubIntrospectModule,
        remote: [url: "https://example.com/graphql", mode: :introspect],
        schema_path: Path.join(tmp_dir, "schema.graphql"),
        schemas_dir: tmp_dir
      }

      assert {:ok, sdl} = Remote.fetch_schema(info)
      assert sdl =~ "type Query"
      assert sdl =~ "hello"
    end
  end
end
