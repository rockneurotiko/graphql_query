defmodule Mix.Tasks.GraphqlQuery.Schema.Check do
  @shortdoc "Checks if local schemas are up-to-date with their remote sources"

  @moduledoc """
  Checks whether locally stored schemas match their remote sources.

  Downloads remote schemas and compares them with the locally stored versions.
  Useful in CI pipelines to detect schema drift.

  Returns exit code 1 if any schemas differ or are missing locally.

  ## Usage

      # Check all remote schemas
      mix graphql_query.schema.check

      # Check a specific schema module
      mix graphql_query.schema.check MyApp.ExternalSchema

  ## Configuration

  Schema modules must be configured with the `:remote` option:

      defmodule MyApp.ExternalSchema do
        use GraphqlQuery.Schema,
          remote: [url: "https://api.example.com/schema.graphql"]
      end
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
      Mix.shell().info("Checking #{length(schemas)} remote schema(s)...\n")

      results = Enum.map(schemas, &check_schema/1)

      up_to_date = Enum.count(results, &(&1 == :match))
      mismatches = Enum.count(results, &(&1 == :mismatch))
      missing = Enum.count(results, &(&1 == :missing))
      errors = Enum.count(results, &(&1 == :error))

      Mix.shell().info("")

      Mix.shell().info(
        "Results: #{up_to_date} up-to-date, #{mismatches} outdated, #{missing} missing, #{errors} errors"
      )

      if mismatches > 0 or missing > 0 or errors > 0 do
        Mix.raise(
          "Schema check failed. #{mismatches} schema(s) outdated, #{missing} missing, #{errors} errors. " <>
            "Run `mix graphql_query.schema.fetch` to update."
        )
      end
    end
  end

  defp check_schema(info) do
    %{module: module, schema_path: schema_path} = info

    Mix.shell().info("Checking #{inspect(module)}...")

    unless File.exists?(schema_path) do
      Mix.shell().error("  ✗ Local file missing: #{schema_path}")
      throw(:missing)
    end

    case Remote.fetch_schema(info) do
      {:ok, remote_content} ->
        if Remote.schemas_match?(schema_path, remote_content) do
          Mix.shell().info("  ✓ Up to date")
          :match
        else
          Mix.shell().error("  ✗ Schema differs from remote")
          :mismatch
        end

      {:error, reason} ->
        Mix.shell().error("  ✗ Failed to fetch remote: #{reason}")
        :error
    end
  catch
    :missing -> :missing
  end

  defp parse_module_filter([]), do: nil

  defp parse_module_filter([module_string | _]) do
    module_string =
      if String.starts_with?(module_string, "Elixir."),
        do: module_string,
        else: "Elixir." <> module_string

    String.to_atom(module_string)
  end
end
