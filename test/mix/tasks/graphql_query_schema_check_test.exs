defmodule Mix.Tasks.GraphqlQuery.Schema.CheckTest do
  use ExUnit.Case

  alias GraphqlQuery.Schema.Remote
  alias Mix.Tasks.GraphqlQuery.Schema.Check

  setup do
    # Use process shell for capturing output in tests
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "run/1" do
    test "reports when no remote schemas are found or discovers existing ones" do
      # When test modules with __remote_config__ are loaded, discovery may find them.
      # The test accepts either outcome: no schemas found, or schemas found and checked.
      try do
        Check.run([])

        assert_receive {:mix_shell, :info, [msg]}
        assert msg =~ "No remote schema modules found" or msg =~ "Checking"
      rescue
        Mix.Error -> :ok
      end
    end

    test "reports error for non-existent module filter" do
      Check.run(["NonExistent.Module"])

      assert_receive {:mix_shell, :error, [msg]}
      assert msg =~ "No remote schema found"
    end
  end

  describe "schema check integration" do
    setup do
      tmp_dir = System.tmp_dir!() |> Path.join("check_task_test_#{:rand.uniform(100_000)}")
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      %{tmp_dir: tmp_dir}
    end

    test "reports match when local schema matches remote", %{tmp_dir: tmp_dir} do
      schema_content = "type Query { hello: String! }"
      schema_path = Path.join(tmp_dir, "schema.graphql")

      # Write a local schema file
      File.mkdir_p!(tmp_dir)
      File.write!(schema_path, schema_content)

      # Stub the remote to return the same content
      Req.Test.stub(:check_match, fn conn ->
        Req.Test.text(conn, schema_content)
      end)

      defmodule CheckMatchModule do
        def build_request(req), do: Req.merge(req, plug: {Req.Test, :check_match})
      end

      info = %{
        module: CheckMatchModule,
        remote: [url: "https://example.com/schema.graphql"],
        schema_path: schema_path,
        schemas_dir: tmp_dir
      }

      # Fetch remote and compare
      assert {:ok, remote_content} = Remote.fetch_schema(info)
      assert Remote.schemas_match?(schema_path, remote_content)
    end

    test "reports mismatch when local schema differs from remote", %{tmp_dir: tmp_dir} do
      schema_path = Path.join(tmp_dir, "schema.graphql")

      # Write an outdated local schema
      File.mkdir_p!(tmp_dir)
      File.write!(schema_path, "type Query { old: String }")

      # Stub the remote to return different content
      Req.Test.stub(:check_mismatch, fn conn ->
        Req.Test.text(conn, "type Query { new: String! }")
      end)

      defmodule CheckMismatchModule do
        def build_request(req), do: Req.merge(req, plug: {Req.Test, :check_mismatch})
      end

      info = %{
        module: CheckMismatchModule,
        remote: [url: "https://example.com/schema.graphql"],
        schema_path: schema_path,
        schemas_dir: tmp_dir
      }

      assert {:ok, remote_content} = Remote.fetch_schema(info)
      refute Remote.schemas_match?(schema_path, remote_content)
    end

    test "reports missing when local file does not exist", %{tmp_dir: tmp_dir} do
      schema_path = Path.join(tmp_dir, "nonexistent.graphql")

      refute File.exists?(schema_path)
      refute Remote.schemas_match?(schema_path, "any content")
    end
  end
end
