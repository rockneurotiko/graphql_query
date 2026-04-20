defmodule GraphqlQuery.Schema.Remote do
  @moduledoc """
  Utilities for managing remote GraphQL schemas.

  Provides functions for deriving schema file paths from module names,
  resolving schema directory configuration, discovering remote schema modules,
  fetching remote schema content, and managing schema files on disk.

  ## Configuration

  The schemas directory can be configured at multiple levels (in order of precedence):

  1. Per-module `:schemas_dir` option in `use GraphqlQuery.Schema`
  2. Application config: `config :graphql_query, schemas_dir: "priv/graphql/schemas"`
  3. Default: `"priv/graphql/schemas"`

  ## File Path Derivation

  Module names are converted to underscored/nested file paths:

  - `MyApp.ExternalSchema` → `<schemas_dir>/my_app/external_schema.graphql`
  - `MyApp.GitHub.Schema` → `<schemas_dir>/my_app/git_hub/schema.graphql`
  """

  alias GraphqlQuery.Schema.Remote.HttpClient

  @default_schemas_dir "priv/graphql/schemas"

  @doc """
  Returns the default schemas directory path.
  """
  @spec default_schemas_dir() :: String.t()
  def default_schemas_dir, do: @default_schemas_dir

  @doc """
  Resolves the schemas directory from the given option, application config, or default.

  ## Resolution Order

  1. The `module_opt` value if not `nil`
  2. Application config: `config :graphql_query, schemas_dir: "..."`
  3. Default: `"priv/graphql/schemas"`

  ## Examples

      iex> GraphqlQuery.Schema.Remote.resolve_schemas_dir("custom/path")
      "custom/path"

      iex> GraphqlQuery.Schema.Remote.resolve_schemas_dir(nil)
      "priv/graphql/schemas"

  """
  @spec resolve_schemas_dir(String.t() | nil) :: String.t()
  def resolve_schemas_dir(module_opt) when is_binary(module_opt), do: module_opt

  def resolve_schemas_dir(nil) do
    Application.get_env(:graphql_query, :schemas_dir, @default_schemas_dir)
  end

  @doc """
  Derives a schema file path from a module name and schemas directory.

  Converts the module name to an underscored/nested path structure with a `.graphql` extension.

  ## Examples

      iex> GraphqlQuery.Schema.Remote.derive_schema_path(MyApp.ExternalSchema, "priv/graphql/schemas")
      "priv/graphql/schemas/my_app/external_schema.graphql"

      iex> GraphqlQuery.Schema.Remote.derive_schema_path(MyApp.GitHub.Schema, "priv/schemas")
      "priv/schemas/my_app/git_hub/schema.graphql"

  """
  @spec derive_schema_path(module(), String.t()) :: String.t()
  def derive_schema_path(module, schemas_dir) when is_atom(module) and is_binary(schemas_dir) do
    module
    |> module_to_path_parts()
    |> then(fn parts ->
      filename = List.last(parts) <> ".graphql"
      dir_parts = Enum.drop(parts, -1)
      Path.join([schemas_dir | dir_parts] ++ [filename])
    end)
  end

  @doc """
  Discovers all compiled modules that have remote schema configuration.

  Scans all loaded applications and their modules for those that export
  a `__remote_config__/0` function, indicating they have remote schema setup.

  Returns a list of maps with module info including the module, remote config,
  schemas directory, and derived file path.

  ## Examples

      iex> GraphqlQuery.Schema.Remote.discover_remote_schemas()
      [
        %{
          module: MyApp.ExternalSchema,
          remote: [url: "https://api.example.com/schema.graphql"],
          schemas_dir: "priv/graphql/schemas",
          schema_path: "priv/graphql/schemas/my_app/external_schema.graphql"
        }
      ]

  """
  @spec discover_remote_schemas() :: [map()]
  def discover_remote_schemas do
    # Scan all loaded OTP applications and ensure each registered module
    # is loaded into the VM before checking for __remote_config__/0.
    # BEAM lazily loads modules, so function_exported?/3 returns false
    # for modules that are compiled but not yet loaded into memory.
    for {app, _desc, _vsn} <- Application.loaded_applications(),
        {:ok, modules} <- [:application.get_key(app, :modules)],
        module <- modules,
        Code.ensure_loaded?(module),
        function_exported?(module, :__remote_config__, 0) do
      module_remote_info(module)
    end
  end

  @doc """
  Returns remote schema information for a specific module.

  ## Examples

      iex> GraphqlQuery.Schema.Remote.module_remote_info(MyApp.ExternalSchema)
      %{
        module: MyApp.ExternalSchema,
        remote: [url: "https://api.example.com/schema.graphql"],
        schemas_dir: "priv/graphql/schemas",
        schema_path: "priv/graphql/schemas/my_app/external_schema.graphql"
      }

  """
  @spec module_remote_info(module()) :: map()
  def module_remote_info(module) do
    remote = module.__remote_config__()
    schemas_dir = module.__schemas_dir__()
    schema_path = module.schema_path()

    %{
      module: module,
      remote: remote,
      schemas_dir: schemas_dir,
      schema_path: schema_path
    }
  end

  @doc """
  Fetches the SDL content for a remote schema.

  Accepts the info map produced by `module_remote_info/1` (or `discover_remote_schemas/0`).
  Resolves the URL at runtime (supporting both plain strings and `{Module, :function}` tuples),
  selects the correct HTTP strategy based on `:mode`, and delegates to the module's
  `build_request/1` callback for request customisation.

  Returns `{:ok, sdl}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> info = GraphqlQuery.Schema.Remote.module_remote_info(MyApp.ExternalSchema)
      iex> GraphqlQuery.Schema.Remote.fetch_schema(info)
      {:ok, "type Query { ... }"}

  """
  @spec fetch_schema(map()) :: {:ok, String.t()} | {:error, String.t()}
  def fetch_schema(%{module: module, remote: remote}) do
    url = remote |> Keyword.fetch!(:url) |> resolve_url()
    mode = Keyword.get(remote, :mode, :fetch)

    case mode do
      :fetch -> HttpClient.fetch(url, module)
      :introspect -> HttpClient.introspect(url, module)
    end
  end

  @doc """
  Resolves a remote URL at runtime.

  Accepts either a plain string URL or a `{Module, :function}` tuple. When a
  tuple is given the function is called with no arguments and its return value
  (which must be a non-empty string) is used as the URL.

  ## Examples

      iex> GraphqlQuery.Schema.Remote.resolve_url("https://example.com/schema.graphql")
      "https://example.com/schema.graphql"

      iex> GraphqlQuery.Schema.Remote.resolve_url({Application, :get_env})
      # calls Application.get_env() at runtime

  """
  @spec resolve_url(String.t() | {module(), atom()}) :: String.t()
  def resolve_url(url) when is_binary(url), do: url

  def resolve_url({mod, fun}) when is_atom(mod) and is_atom(fun) do
    result = apply(mod, fun, [])

    unless is_binary(result) and result != "" do
      raise ArgumentError,
        message:
          "#{inspect(mod)}.#{fun}/0 must return a non-empty string URL, got: #{inspect(result)}"
    end

    result
  end

  @doc """
  Saves schema content to the given file path, creating directories as needed.

  ## Examples

      iex> GraphqlQuery.Schema.Remote.save_schema("/tmp/test_schema.graphql", "type Query { hello: String }")
      :ok

  """
  @spec save_schema(String.t(), String.t()) :: :ok | {:error, term()}
  def save_schema(path, content) when is_binary(path) and is_binary(content) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write(path, content)
  end

  @doc """
  Checks whether the stored schema file matches the given content.

  Returns `true` if the file exists and its content matches exactly,
  `false` otherwise (including when the file doesn't exist).

  ## Examples

      iex> File.write!("/tmp/test_match.graphql", "type Query { hello: String }")
      iex> GraphqlQuery.Schema.Remote.schemas_match?("/tmp/test_match.graphql", "type Query { hello: String }")
      true

      iex> GraphqlQuery.Schema.Remote.schemas_match?("/tmp/nonexistent.graphql", "content")
      false

  """
  @spec schemas_match?(String.t(), String.t()) :: boolean()
  def schemas_match?(path, content) when is_binary(path) and is_binary(content) do
    case File.read(path) do
      {:ok, stored} -> stored == content
      {:error, _} -> false
    end
  end

  # Converts a module name like MyApp.ExternalSchema to ["my_app", "external_schema"]
  defp module_to_path_parts(module) do
    module
    |> Module.split()
    |> Enum.map(&Macro.underscore/1)
  end
end
