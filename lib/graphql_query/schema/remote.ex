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

      iex> GraphqlQuery.Schema.Remote.resolve_url({Module, :url})
      # calls Module.url() at runtime

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
    with :ok <- path |> Path.dirname() |> File.mkdir_p() do
      File.write(path, content)
    end
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

  # ---------------------------------------------------------------------------
  # Compile-time helpers
  #
  # These functions are called from `GraphqlQuery.Schema.__using__/1` during
  # compilation to generate the AST injected into modules that declare
  # `remote: [...]`.
  # ---------------------------------------------------------------------------

  @valid_remote_keys [:url, :mode]
  @valid_modes [:fetch, :introspect]

  @doc """
  Generates the quoted AST block for a remote schema module.

  Called by `GraphqlQuery.Schema.__using__/1` when the `:remote` option is
  present. Validates the remote configuration, resolves file paths, warns if
  the local schema file is missing, and returns a quoted block that defines
  `__remote_config__/0`, `__schemas_dir__/0`, `build_request/1`, `schema/0`,
  and `schema_path/0` on the caller module.

  ## Parameters

    * `remote` — the keyword list passed as the `:remote` option
    * `schemas_dir_opt` — the optional `:schemas_dir` override (or `nil`)
    * `module` — the caller module atom (`__CALLER__.module`)
    * `explicit_path` — an explicit `:schema_path` value (or `nil`)
  """
  @spec compile_ast(keyword(), String.t() | nil, module(), String.t() | nil) :: Macro.t()
  def compile_ast(remote, schemas_dir_opt, module, explicit_path) do
    unless Code.ensure_loaded?(Req) do
      raise CompileError,
        description:
          "The :remote option requires the :req dependency. " <>
            "Add {:req, \"~> 0.5\"} to your mix.exs deps."
    end

    validate_config!(remote)

    {schema_path, schemas_dir} = resolve_schema_paths(explicit_path, schemas_dir_opt, module)

    warn_if_schema_missing(schema_path, module)

    schema_fn_ast = build_schema_fn_ast(schema_path)

    quote do
      @external_resource unquote(schema_path)

      def __remote_config__, do: unquote(remote)
      def __schemas_dir__, do: unquote(schemas_dir)

      @doc """
      Customizes the HTTP request before fetching the remote schema.

      Override this function to add authentication, custom headers, or any
      other request modifications. Receives a `%Req.Request{}` and must return
      a `%Req.Request{}`.

      The default implementation is a passthrough (no modifications).

      ## Examples

          # Authentication and custom header example
          def build_request(req) do
            req
            |> Req.merge(auth: {:bearer, "token"})
            |> Req.Request.put_header("x-api-key", "my-key")
          end
      """
      @spec build_request(Req.Request.t()) :: Req.Request.t()
      def build_request(req), do: req
      defoverridable build_request: 1

      unquote(schema_fn_ast)

      @impl GraphqlQuery.Schema
      def schema_path, do: unquote(schema_path)
    end
  end

  @doc """
  Resolves the schema file path and schemas directory for a remote module.

  When `explicit_path` is provided, it is used directly and `schemas_dir` is
  `nil`. Otherwise, the path is derived from the module name using
  `derive_schema_path/2` and the resolved schemas directory.

  Returns a `{schema_path, schemas_dir}` tuple.
  """
  @spec resolve_schema_paths(String.t() | nil, String.t() | nil, module()) ::
          {String.t(), String.t() | nil}
  def resolve_schema_paths(explicit_path, schemas_dir_opt, module) do
    if explicit_path do
      {explicit_path, nil}
    else
      schemas_dir = resolve_schemas_dir(schemas_dir_opt)
      {derive_schema_path(module, schemas_dir), schemas_dir}
    end
  end

  @doc """
  Emits a compile-time warning when a remote schema file does not exist locally.

  Called during compilation to alert developers that the schema needs to be
  fetched with `mix graphql_query.schema.fetch`.
  """
  @spec warn_if_schema_missing(String.t(), module()) :: :ok
  def warn_if_schema_missing(schema_path, module) do
    unless File.exists?(schema_path) do
      IO.warn("""
      Remote schema file not found: #{schema_path}

      Module #{inspect(module)} is configured with a remote schema but the local file
      has not been downloaded yet.

      Run the following command to fetch remote schemas:

          mix graphql_query.schema.fetch

      Or fetch only this schema:

          mix graphql_query.schema.fetch #{inspect(module)}
      """)
    end

    :ok
  end

  @doc """
  Builds the `schema/0` function AST for a remote schema module.

  When the local schema file exists at compile time, generates a function that
  loads it via `gql_from_file/2`. When it does not exist, generates a function
  that raises `GraphqlQuery.Schema.RemoteNotFetchedError`.
  """
  @spec build_schema_fn_ast(String.t()) :: Macro.t()
  def build_schema_fn_ast(schema_path) do
    if File.exists?(schema_path) do
      quote do
        @impl GraphqlQuery.Schema
        def schema do
          gql_from_file(unquote(schema_path), type: :schema)
        end
      end
    else
      quote do
        @impl GraphqlQuery.Schema
        def schema do
          raise GraphqlQuery.Schema.RemoteNotFetchedError,
            module: __MODULE__,
            schema_path: unquote(schema_path)
        end
      end
    end
  end

  @doc """
  Validates the `:remote` configuration keyword list.

  Raises `CompileError` when:

    * the value is not a keyword list
    * the `:url` key is missing
    * unknown keys are present (valid keys: `#{inspect(@valid_remote_keys)}`)
    * the `:url` value is not a non-empty string or `{Module, :function}` tuple
    * the `:mode` value is not one of `#{inspect(@valid_modes)}`
  """
  @spec validate_config!(keyword()) :: :ok
  def validate_config!(remote) do
    unless Keyword.keyword?(remote) do
      raise CompileError,
        description: "The :remote option must be a keyword list, got: #{inspect(remote)}"
    end

    unless Keyword.has_key?(remote, :url) do
      raise CompileError,
        description: "The :remote option must include a :url key, got: #{inspect(remote)}"
    end

    unknown_keys = Keyword.keys(remote) -- @valid_remote_keys

    if unknown_keys != [] do
      raise CompileError,
        description:
          "The :remote option contains unknown keys: #{inspect(unknown_keys)}. " <>
            "Valid keys are: #{inspect(@valid_remote_keys)}"
    end

    url = Keyword.get(remote, :url)

    unless valid_url?(url) do
      raise CompileError,
        description:
          "The :remote :url must be a non-empty string or a {Module, :function} tuple, " <>
            "got: #{inspect(url)}"
    end

    mode = Keyword.get(remote, :mode, :fetch)

    unless mode in @valid_modes do
      raise CompileError,
        description:
          "The :remote :mode must be one of #{inspect(@valid_modes)}, got: #{inspect(mode)}"
    end

    :ok
  end

  @doc """
  Checks whether a URL value is valid for the `:remote` `:url` option.

  Accepts non-empty binary strings and `{Module, :function}` tuples.
  """
  @spec valid_url?(term()) :: boolean()
  def valid_url?(url) when is_binary(url) and url != "", do: true
  # Accept {Module, :function} tuples; the first element may be an alias AST at
  # compile time, so we only guard on the function name being an atom. Full
  # resolution happens at runtime via resolve_url/1.
  def valid_url?({_mod, fun}) when is_atom(fun), do: true
  def valid_url?(_), do: false

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Converts a module name like MyApp.ExternalSchema to ["my_app", "external_schema"]
  defp module_to_path_parts(module) do
    module
    |> Module.split()
    |> Enum.map(&Macro.underscore/1)
  end
end
