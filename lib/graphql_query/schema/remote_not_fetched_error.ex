defmodule GraphqlQuery.Schema.RemoteNotFetchedError do
  @moduledoc """
  Raised when a remote schema's local file has not been downloaded yet.

  This error is raised by `schema/0` in modules configured with
  `use GraphqlQuery.Schema, remote: [...]` when the local schema file
  doesn't exist. It signals that compile-time schema validation should
  be skipped gracefully rather than crashing compilation.

  Run `mix graphql_query.schema.fetch` to download remote schemas.
  """

  defexception [:module, :schema_path]

  @impl true
  def message(%{module: module, schema_path: schema_path}) do
    """
    Remote schema file not found: #{schema_path}

    Module #{inspect(module)} is configured with a remote schema but the local file
    has not been downloaded yet.

    Run the following command to fetch remote schemas:

        mix graphql_query.schema.fetch

    Or fetch only this schema:

        mix graphql_query.schema.fetch #{inspect(module)}
    """
  end
end
