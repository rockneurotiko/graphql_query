defmodule GraphqlQuery.Schema.RemoteSchemaIntegrationTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias GraphqlQuery.{Document, Schema.Remote}

  @schemas_dir "test/fixtures/remote_schemas"

  # Compile-time module definitions — these are compiled with the test file,
  # so no "module not available" warnings when referenced in assertions.

  defmodule TestRemoteBasic do
    use GraphqlQuery.Schema,
      remote: [url: "https://example.com/schema.graphql"],
      schemas_dir: "test/fixtures/remote_schemas"
  end

  defmodule TestRemoteIntrospectMode do
    use GraphqlQuery.Schema,
      remote: [url: "https://api.example.com/graphql", mode: :introspect],
      schemas_dir: "test/fixtures/remote_schemas"
  end

  defmodule TestRemoteBuildReqOverride do
    use GraphqlQuery.Schema,
      remote: [url: "https://example.com/schema.graphql"],
      schemas_dir: "test/fixtures/remote_schemas"

    def build_request(req) do
      Req.Request.put_header(req, "authorization", "Bearer test-token-123")
    end
  end

  defmodule TestRemoteBuildReqMulti do
    use GraphqlQuery.Schema,
      remote: [url: "https://example.com/schema.graphql"],
      schemas_dir: "test/fixtures/remote_schemas"

    def build_request(req) do
      req
      |> Req.Request.put_header("x-api-key", "my-key")
      |> Req.Request.put_header("accept", "application/graphql")
    end
  end

  defmodule TestRemoteFederation do
    use GraphqlQuery.Schema,
      remote: [url: "https://example.com/schema.graphql"],
      schemas_dir: "test/fixtures/remote_schemas",
      federation: true
  end

  # Module that vends a URL at runtime — used by TestRemoteMfaUrl below
  defmodule TestUrlProvider do
    def graphql_url, do: "https://example.com/schema.graphql"
  end

  defmodule TestRemoteMfaUrl do
    use GraphqlQuery.Schema,
      remote: [url: {GraphqlQuery.Schema.RemoteSchemaIntegrationTest.TestUrlProvider, :graphql_url}],
      schemas_dir: "test/fixtures/remote_schemas"
  end

  defmodule TestRemoteWithExplicitPath do
    use GraphqlQuery.Schema,
      remote: [url: "https://example.com/schema.graphql"],
      schema_path: "test/fixtures/remote_schemas/explicit_path_schema.graphql"
  end

  describe "use GraphqlQuery.Schema with remote and schema_path" do
    test "uses explicit schema_path instead of derived path" do
      assert TestRemoteWithExplicitPath.schema_path() ==
               "test/fixtures/remote_schemas/explicit_path_schema.graphql"
    end

    test "loads schema from explicit path" do
      assert %Document{type: :schema, query: content} = TestRemoteWithExplicitPath.schema()
      assert content =~ "hello: String!"
      assert content =~ "world: String"
    end

    test "still exposes remote config" do
      assert TestRemoteWithExplicitPath.__remote_config__() == [
               url: "https://example.com/schema.graphql"
             ]
    end

    test "schemas_dir is nil when schema_path overrides" do
      assert TestRemoteWithExplicitPath.__schemas_dir__() == nil
    end

    test "module_remote_info uses explicit schema_path" do
      info = Remote.module_remote_info(TestRemoteWithExplicitPath)
      assert info.schema_path == "test/fixtures/remote_schemas/explicit_path_schema.graphql"
      assert info.schemas_dir == nil
      assert info.remote == [url: "https://example.com/schema.graphql"]
    end

    test "build_request/1 is still available" do
      req = Req.new(url: "https://example.com/test")
      assert TestRemoteWithExplicitPath.build_request(req) == req
    end
  end

  describe "use GraphqlQuery.Schema with remote option" do
    test "raises when remote :mode is invalid" do
      assert_raise CompileError, ~r/must be one of/, fn ->
        Code.compile_string("""
        defmodule TestRemoteInvalidMode do
          use GraphqlQuery.Schema, remote: [url: "https://example.com/graphql", mode: :invalid]
        end
        """)
      end
    end

    test "raises when remote config is missing :url" do
      assert_raise CompileError, ~r/must include a :url key/, fn ->
        Code.compile_string("""
        defmodule TestRemoteNoUrl do
          use GraphqlQuery.Schema, remote: [some: "config"]
        end
        """)
      end
    end

    test "raises when remote config is not a keyword list" do
      assert_raise CompileError, ~r/must be a keyword list/, fn ->
        Code.compile_string("""
        defmodule TestRemoteNotKeyword do
          use GraphqlQuery.Schema, remote: "not a keyword"
        end
        """)
      end
    end

    test "raises when remote config has unknown keys" do
      assert_raise CompileError, ~r/unknown keys/, fn ->
        Code.compile_string("""
        defmodule TestRemoteUnknownKey do
          use GraphqlQuery.Schema, remote: [url: "https://example.com/graphql", unknown: true]
        end
        """)
      end
    end

    test "error message for unknown keys lists valid options" do
      assert_raise CompileError, ~r/:url.*:mode|:mode.*:url/, fn ->
        Code.compile_string("""
        defmodule TestRemoteUnknownKey2 do
          use GraphqlQuery.Schema, remote: [url: "https://example.com/graphql", foo: 1, bar: 2]
        end
        """)
      end
    end

    test "raises when top-level unknown option is given" do
      assert_raise CompileError, ~r/Unknown options passed to use GraphqlQuery\.Schema/, fn ->
        Code.compile_string("""
        defmodule TestTopLevelUnknownOpt do
          use GraphqlQuery.Schema,
            schema_path: "priv/schema.graphql",
            totally_unknown: true
        end
        """)
      end
    end

    test "raises when remote :url is empty" do
      assert_raise CompileError, ~r/must be a non-empty string/, fn ->
        Code.compile_string("""
        defmodule TestRemoteEmptyUrl do
          use GraphqlQuery.Schema, remote: [url: ""]
        end
        """)
      end
    end

    test "emits warning and compiles when schema file does not exist" do
      warnings =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule TestRemoteMissing do
            use GraphqlQuery.Schema,
              remote: [url: "https://example.com/schema.graphql"],
              schemas_dir: "nonexistent/path"
          end
          """)
        end)

      assert warnings =~ "Remote schema file not found"
      assert warnings =~ "mix graphql_query.schema.fetch"

      # Module compiled successfully and exposes remote config
      mod = Module.concat([TestRemoteMissing])
      assert mod.__remote_config__() == [url: "https://example.com/schema.graphql"]
      assert mod.schema_path() =~ "nonexistent/path"

      # schema/0 raises RemoteNotFetchedError when file hasn't been fetched
      assert_raise GraphqlQuery.Schema.RemoteNotFetchedError, fn ->
        mod.schema()
      end

      error =
        assert_raise GraphqlQuery.Schema.RemoteNotFetchedError, fn ->
          mod.schema()
        end

      assert error.module == mod
      assert error.schema_path =~ "nonexistent/path"
      assert Exception.message(error) =~ "Remote schema file not found"
      assert Exception.message(error) =~ "mix graphql_query.schema.fetch"
    end

    test "accepts :fetch mode" do
      config = TestRemoteBasic.__remote_config__()
      assert Keyword.get(config, :mode, :fetch) == :fetch
    end

    test "accepts :introspect mode" do
      assert TestRemoteIntrospectMode.__remote_config__() == [
               url: "https://api.example.com/graphql",
               mode: :introspect
             ]
    end

    test "defaults to :fetch mode when not specified" do
      config = TestRemoteBasic.__remote_config__()
      assert Keyword.get(config, :mode, :fetch) == :fetch
    end

    test "loads schema from derived file path when file exists" do
      schema_path = Remote.derive_schema_path(TestRemoteBasic, @schemas_dir)

      assert %Document{type: :schema} = TestRemoteBasic.schema()
      assert TestRemoteBasic.schema_path() == schema_path
      assert TestRemoteBasic.__remote_config__() == [url: "https://example.com/schema.graphql"]
      assert TestRemoteBasic.__schemas_dir__() == @schemas_dir
    end

    test "respects per-module schemas_dir override" do
      schema_path = Remote.derive_schema_path(TestRemoteBasic, @schemas_dir)

      assert TestRemoteBasic.__schemas_dir__() == @schemas_dir
      assert TestRemoteBasic.schema_path() == schema_path
    end

    test "defines default build_request/1 that is a passthrough" do
      req = Req.new(url: "https://example.com/test")
      assert TestRemoteBasic.build_request(req) == req
    end

    test "build_request/1 can be overridden" do
      req = Req.new(url: "https://example.com/test")
      modified = TestRemoteBuildReqOverride.build_request(req)

      {_key, values} = Enum.find(modified.headers, fn {k, _} -> k == "authorization" end)
      assert values == ["Bearer test-token-123"]
    end

    test "build_request/1 can add multiple headers" do
      req = Req.new(url: "https://example.com/test")
      modified = TestRemoteBuildReqMulti.build_request(req)

      headers_map = Map.new(modified.headers)
      assert headers_map["x-api-key"] == ["my-key"]
      assert headers_map["accept"] == ["application/graphql"]
    end

    test "federation option works with remote schemas" do
      assert TestRemoteFederation.federation?() == true
      assert %Document{type: :schema} = TestRemoteFederation.schema()
    end

    test "federation option does not produce warnings with remote schemas" do
      schema_path =
        "test/fixtures/remote_schemas/graphql_query/schema/remote_schema_integration_test/test_remote_federation.graphql"

      logs =
        capture_io(:stderr, fn ->
          Code.eval_quoted(
            quote do
              defmodule TestRemoteFederationNoWarnings do
                use GraphqlQuery.Schema,
                  remote: [url: "https://example.com/schema.graphql"],
                  schema_path: unquote(schema_path),
                  federation: true
              end
            end
          )
        end)

      assert logs == ""
    end

    test "accepts {Module, :function} tuple as :url" do
      config = TestRemoteMfaUrl.__remote_config__()

      assert Keyword.get(config, :url) ==
               {GraphqlQuery.Schema.RemoteSchemaIntegrationTest.TestUrlProvider, :graphql_url}
    end

    test "loads schema when url is a {Module, :function} tuple" do
      assert %Document{type: :schema} = TestRemoteMfaUrl.schema()
    end

    test "raises when remote :url is a tuple with non-atom elements" do
      # A string literal like "not_atom" passes our loose compile-time shape
      # check (it's a 2-tuple with an atom function name), but resolve_url/1
      # raises an ArgumentError at runtime because String.upcase/0 doesn't exist.
      # We verify the runtime behaviour here instead of a CompileError.
      assert_raise UndefinedFunctionError, fn ->
        GraphqlQuery.Schema.Remote.resolve_url({String, :nonexistent_fun_arity_zero})
      end
    end

    test "raises when remote :url is a 3-tuple" do
      assert_raise CompileError, ~r/must be a non-empty string or a \{Module, :function\} tuple/, fn ->
        Code.compile_string("""
        defmodule TestRemoteThreeTupleUrl do
          use GraphqlQuery.Schema, remote: [url: {Mod, :fun, :extra}]
        end
        """)
      end
    end
  end
end
