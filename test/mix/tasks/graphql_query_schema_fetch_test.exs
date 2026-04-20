defmodule Mix.Tasks.GraphqlQuery.Schema.FetchTest do
  use ExUnit.Case

  alias Mix.Tasks.GraphqlQuery.Schema.Fetch

  setup do
    # Use process shell for capturing output in tests
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "run/1" do
    test "reports when no remote schemas are found" do
      Fetch.run([])

      assert_receive {:mix_shell, :info, [msg]}
      assert msg =~ "No remote schema modules found" or msg =~ "Found"
    end

    test "reports error for non-existent module filter" do
      Fetch.run(["NonExistent.Module"])

      assert_receive {:mix_shell, :error, [msg]}
      assert msg =~ "No remote schema found"
    end

    test "handles module name with Elixir prefix" do
      Fetch.run(["Elixir.NonExistent.Module"])

      assert_receive {:mix_shell, :error, [msg]}
      assert msg =~ "No remote schema found"
    end
  end

  describe "fetch and save integration" do
    setup do
      tmp_dir = System.tmp_dir!() |> Path.join("fetch_task_test_#{:rand.uniform(100_000)}")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      %{tmp_dir: tmp_dir}
    end

    test "fetches schema via stub and saves to disk", %{tmp_dir: tmp_dir} do
      schema_content = "type Query { hello: String! }"
      schema_path = Path.join(tmp_dir, "fetched_schema.graphql")

      Req.Test.stub(:fetch_task_ok, fn conn ->
        Req.Test.text(conn, schema_content)
      end)

      defmodule FetchTaskStubModule do
        def build_request(req), do: Req.merge(req, plug: {Req.Test, :fetch_task_ok})
      end

      info = %{
        module: FetchTaskStubModule,
        remote: [url: "https://example.com/schema.graphql"],
        schema_path: schema_path,
        schemas_dir: tmp_dir
      }

      # Simulate what the fetch task does internally
      assert {:ok, content} = GraphqlQuery.Schema.Remote.fetch_schema(info)
      assert :ok = GraphqlQuery.Schema.Remote.save_schema(schema_path, content)

      # Verify file was written correctly
      assert File.exists?(schema_path)
      assert File.read!(schema_path) == schema_content
    end

    test "fetches schema via introspection stub and saves to disk", %{tmp_dir: tmp_dir} do
      schema_path = Path.join(tmp_dir, "introspected_schema.graphql")

      Req.Test.stub(:fetch_task_introspect, fn conn ->
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

      defmodule FetchTaskIntrospectModule do
        def build_request(req), do: Req.merge(req, plug: {Req.Test, :fetch_task_introspect})
      end

      info = %{
        module: FetchTaskIntrospectModule,
        remote: [url: "https://example.com/graphql", mode: :introspect],
        schema_path: schema_path,
        schemas_dir: tmp_dir
      }

      assert {:ok, content} = GraphqlQuery.Schema.Remote.fetch_schema(info)
      assert :ok = GraphqlQuery.Schema.Remote.save_schema(schema_path, content)

      assert File.exists?(schema_path)
      saved = File.read!(schema_path)
      assert saved =~ "type Query"
      assert saved =~ "hello"
    end
  end
end
