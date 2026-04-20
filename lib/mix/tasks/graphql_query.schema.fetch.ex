defmodule Mix.Tasks.GraphqlQuery.Schema.Fetch do
  @shortdoc "Fetches remote GraphQL schemas and saves them locally"

  @moduledoc """
  Fetches remote GraphQL schemas and saves them to the local filesystem.

  Discovers all modules that use `GraphqlQuery.Schema` with a `:remote` configuration
  and downloads their schemas from the configured URLs.

  ## Usage

      # Fetch all remote schemas
      mix graphql_query.schema.fetch

      # Fetch a specific schema module
      mix graphql_query.schema.fetch MyApp.ExternalSchema

  ## Configuration

  Schema modules must be configured with the `:remote` option:

      defmodule MyApp.ExternalSchema do
        use GraphqlQuery.Schema,
          remote: [url: "https://api.example.com/schema.graphql"]
      end

  For APIs that only support introspection (no direct SDL endpoint):

      defmodule MyApp.IntrospectedSchema do
        use GraphqlQuery.Schema,
          remote: [url: "https://api.example.com/graphql", mode: :introspect]
      end

  The schemas directory can be configured at multiple levels:

  1. Per-module `:schemas_dir` option in `use GraphqlQuery.Schema`
  2. Application config: `config :graphql_query, schemas_dir: "priv/graphql/schemas"`
  3. Default: `"priv/graphql/schemas"`
  """

  use Mix.Task

  alias GraphqlQuery.Schema.Remote

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile", [])
    Mix.Task.run("app.start", [])

    module_filter = parse_module_filter(args)

    schemas = Remote.discover_remote_schemas()

    schemas =
      if module_filter do
        Enum.filter(schemas, fn info -> info.module == module_filter end)
      else
        schemas
      end

    if Enum.empty?(schemas) do
      if module_filter do
        Mix.shell().error(
          "No remote schema found for module #{inspect(module_filter)}. " <>
            "Make sure the module uses `use GraphqlQuery.Schema, remote: [url: \"...\"]`."
        )
      else
        Mix.shell().info("No remote schema modules found.")
      end
    else
      Mix.shell().info("Found #{length(schemas)} remote schema(s) to fetch.\n")

      results = Enum.map(schemas, &fetch_and_save/1)

      successes = Enum.count(results, &(&1 == :ok))
      failures = length(results) - successes

      Mix.shell().info("")

      if failures > 0 do
        Mix.raise("Schema fetch failed: #{successes} succeeded, #{failures} failed.")
      else
        Mix.shell().info("All #{successes} schema(s) fetched successfully.")
      end
    end
  end

  defp fetch_and_save(info) do
    %{module: module, remote: remote, schema_path: schema_path} = info

    Mix.shell().info(
      "Fetching schema for #{inspect(module)} " <>
        "from #{format_url(Keyword.fetch!(remote, :url))} " <>
        "(#{Keyword.get(remote, :mode, :fetch)})..."
    )

    case Remote.fetch_schema(info) do
      {:ok, content} ->
        case Remote.save_schema(schema_path, content) do
          :ok ->
            Mix.shell().info("  ✓ Saved to #{schema_path}")
            :ok

          {:error, reason} ->
            Mix.shell().error("  ✗ Failed to save to #{schema_path}: #{inspect(reason)}")
            :error
        end

      {:error, reason} ->
        Mix.shell().error("  ✗ Failed to fetch: #{reason}")
        :error
    end
  end

  # Format URL for display: show plain strings as-is, MFA tuples as Module.fun/0.
  defp format_url(url) when is_binary(url), do: url
  defp format_url({mod, fun}), do: "#{inspect(mod)}.#{fun}/0"

  defp parse_module_filter([]), do: nil

  defp parse_module_filter([module_string | _]) do
    module_string =
      if String.starts_with?(module_string, "Elixir."),
        do: module_string,
        else: "Elixir." <> module_string

    String.to_atom(module_string)
  end
end
