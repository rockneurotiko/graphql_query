defmodule GraphqlQuery.Schema.RemoteSyncTest do
  use ExUnit.Case, async: false

  alias GraphqlQuery.Schema.Remote

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
end
