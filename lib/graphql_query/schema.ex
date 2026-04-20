defmodule GraphqlQuery.Schema do
  @moduledoc """
  Behaviour and utilities for GraphQL schema management.

  Defines the contract for modules that provide GraphQL schemas and includes
  a `__using__` macro for easy schema module setup with automatic file loading
  and validation.

  Options for `use GraphqlQuery.Schema`:

    * `:schema_path` - Path to a `.graphql` or `.gql` schema file to load.
    * `:absinthe_schema` - An Absinthe schema module to extract the schema from.
    * `:remote` - Keyword list with remote schema configuration. Requires at least `:url`.
      Supports `:mode` option — `:fetch` (default, GET SDL directly) or `:introspect`
      (POST introspection query, convert JSON response to SDL).
      The schema file is auto-derived from the module name and stored locally.
      Use `mix graphql_query.schema.fetch` to download remote schemas.
    * `:schemas_dir` - Directory for storing remote schemas (used with `:remote`).
      Defaults to application config or `"priv/graphql/schemas"`.
    * `:federation` - Enable Apollo Federation directive support when loading the schema.

  ## Option Combinations

  Some options are mutually exclusive and will raise a `CompileError` if combined:

    * `:absinthe_schema` + `:remote` — cannot be used together
    * `:absinthe_schema` + `:schema_path` — cannot be used together
    * `:schemas_dir` without `:remote` — `:schemas_dir` is only meaningful with `:remote`
    * `:schema_path` + `:remote` + `:schemas_dir` — when `:schema_path` is provided with
      `:remote`, it fully specifies the file location, making `:schemas_dir` redundant

  The valid combination of `:schema_path` + `:remote` uses the explicit path for both
  loading the schema at compile time and as the save target for `mix graphql_query.schema.fetch`,
  overriding the auto-derived path from the module name.

  ## Examples

      defmodule MyApp.Schema do
        use GraphqlQuery.Schema, schema_path: "priv/schema.graphql"
      end

      defmodule MyApp.AbsintheSchema do
        use GraphqlQuery.Schema, absinthe_schema: MyAppWeb.Graphql.Schema
      end

      defmodule MyApp.FederatedSchema do
        use GraphqlQuery.Schema,
          schema_path: "priv/federated_schema.graphql",
          federation: true
      end

      # Remote schema - auto-derives file path from module name
      defmodule MyApp.ExternalApi.Schema do
        use GraphqlQuery.Schema,
          remote: [url: "https://api.example.com/schema.graphql"]
      end
      # Schema file: priv/graphql/schemas/my_app/external_api/schema.graphql
      # Fetch with: mix graphql_query.schema.fetch

      # Remote schema with explicit file path (overrides auto-derived path)
      defmodule MyApp.ExternalApi.CustomPath do
        use GraphqlQuery.Schema,
          remote: [url: "https://api.example.com/schema.graphql"],
          schema_path: "priv/graphql/external_api.graphql"
      end
      # Schema file: priv/graphql/external_api.graphql (explicit, not derived)
      # Fetch saves to the explicit path

      # Remote schema with authentication
      defmodule MyApp.AuthenticatedApi.Schema do
        use GraphqlQuery.Schema,
          remote: [url: "https://api.example.com/schema.graphql"]

        def build_request(req) do
          Req.Request.put_header(req, "authorization", "Bearer " <> System.get_env("API_TOKEN"))
        end
      end

      # The schema will be automatically loaded from the file
      MyApp.Schema.schema()
      #=> %GraphqlQuery.Document{type: :schema, query: "type Query { user(id: ID!): User } ..."

      # For Absinthe, the schema is extracted at compile time
      MyApp.AbsintheSchema.schema()
      #=> %GraphqlQuery.Document{type: :schema, query: "type Query { user(id: ID!): User } ..."

      # Get the file path
      MyApp.Schema.schema_path()
      #=> "priv/schema.graphql"

  """

  @callback schema() :: GraphqlQuery.Document.t()
  @callback schema_path() :: String.t() | nil

  defstruct [:schema, :schema_path]

  alias GraphqlQuery.Schema.Remote

  # Keys consumed directly by GraphqlQuery.Schema; the rest are forwarded to
  # `use GraphqlQuery` and validated there via MacroOptions / NimbleOptions.
  @schema_own_keys [:schema_path, :absinthe_schema, :remote, :schemas_dir]

  # Keys accepted by the underlying `use GraphqlQuery` macro (MacroOptions).
  @graphql_query_keys [
    :ignore,
    :type,
    :schema,
    :evaluate,
    :runtime,
    :fragments,
    :format,
    :federation
  ]

  @valid_schema_keys (@schema_own_keys ++ @graphql_query_keys) |> Enum.uniq()

  defmacro __using__(opts) do
    file_path = Keyword.get(opts, :schema_path)
    absinthe = Keyword.get(opts, :absinthe_schema)
    remote = Keyword.get(opts, :remote)
    schemas_dir_opt = Keyword.get(opts, :schemas_dir)
    federation = Keyword.get(opts, :federation, false)
    extra_opts = Keyword.drop(opts, @schema_own_keys)

    validate_opts!(opts, file_path, absinthe, remote, schemas_dir_opt)

    # Determine which schema source AST to inject — done outside quote
    # to avoid evaluating remote_ast when remote is nil
    schema_source_ast =
      cond do
        remote -> remote_ast(remote, schemas_dir_opt, __CALLER__.module, file_path)
        file_path -> file_path_ast(file_path)
        absinthe -> absinthe_ast(absinthe, __CALLER__.file)
        true -> default_schema_ast(__CALLER__.file)
      end

    quote do
      @behaviour GraphqlQuery.Schema

      use GraphqlQuery, unquote(extra_opts)

      def federation?, do: unquote(federation)

      unquote(schema_source_ast)
    end
  end

  defp default_schema_ast(caller_file) do
    quote do
      @impl GraphqlQuery.Schema
      def schema_path, do: unquote(caller_file)
      defoverridable schema_path: 0
    end
  end

  defp file_path_ast(file_path) do
    quote do
      @impl GraphqlQuery.Schema
      def schema do
        gql_from_file(unquote(file_path), type: :schema)
      end

      @impl GraphqlQuery.Schema
      def schema_path, do: unquote(file_path)
    end
  end

  defp resolve_schema_paths(explicit_path, schemas_dir_opt, module) do
    if explicit_path do
      {explicit_path, nil}
    else
      schemas_dir = Remote.resolve_schemas_dir(schemas_dir_opt)
      {Remote.derive_schema_path(module, schemas_dir), schemas_dir}
    end
  end

  defp warn_if_schema_missing(schema_path, module) do
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
  end

  defp build_schema_fn_ast(schema_path) do
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

  defp remote_ast(remote, schemas_dir_opt, module, explicit_path) do
    unless Code.ensure_loaded?(Req) do
      raise CompileError,
        description:
          "The :remote option requires the :req dependency. " <>
            "Add {:req, \"~> 0.5\"} to your mix.exs deps."
    end

    validate_remote_config!(remote)

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

          # Bearer token
          def build_request(req) do
            Req.Request.put_header(req, "authorization", "Bearer " <> token())
          end

          # Basic auth
          def build_request(req) do
            Req.merge(req, auth: {:basic, "user:pass"})
          end

          # Custom headers
          def build_request(req) do
            req
            |> Req.Request.put_header("x-api-key", "my-key")
            |> Req.Request.put_header("accept", "application/graphql")
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

  defp validate_no_unknown_keys!(opts) do
    unknown_keys = Keyword.keys(opts) -- @valid_schema_keys

    if unknown_keys != [] do
      raise CompileError,
        description:
          "Unknown options passed to use GraphqlQuery.Schema: #{inspect(unknown_keys)}. " <>
            "Valid options are: #{inspect(@valid_schema_keys)}"
    end
  end

  defp validate_absinthe_exclusivity!(absinthe, remote, file_path) do
    if absinthe && remote do
      raise CompileError,
        description:
          "The :absinthe_schema and :remote options are mutually exclusive. " <>
            "Use one or the other, not both."
    end

    if absinthe && file_path do
      raise CompileError,
        description:
          "The :absinthe_schema and :schema_path options are mutually exclusive. " <>
            "Use one or the other, not both."
    end
  end

  defp validate_schemas_dir!(schemas_dir_opt, remote, file_path) do
    if schemas_dir_opt && !remote do
      raise CompileError,
        description:
          "The :schemas_dir option is only meaningful with :remote. " <>
            "Remove :schemas_dir or add a :remote configuration."
    end

    if file_path && remote && schemas_dir_opt do
      raise CompileError,
        description:
          "The :schema_path and :schemas_dir options cannot be used together with :remote. " <>
            "When :schema_path is provided, it fully specifies the file location, " <>
            "making :schemas_dir redundant. Remove :schemas_dir."
    end
  end

  defp validate_opts!(opts, file_path, absinthe, remote, schemas_dir_opt) do
    validate_no_unknown_keys!(opts)
    validate_absinthe_exclusivity!(absinthe, remote, file_path)
    validate_schemas_dir!(schemas_dir_opt, remote, file_path)
  end

  @valid_remote_keys [:url, :mode]
  @valid_modes [:fetch, :introspect]

  defp validate_remote_config!(remote) do
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
  end

  defp valid_url?(url) when is_binary(url) and url != "", do: true
  # Accept {Module, :function} tuples; the first element may be an alias AST at
  # compile time, so we only guard on the function name being an atom. Full
  # resolution happens at runtime via resolve_url/1.
  defp valid_url?({_mod, fun}) when is_atom(fun), do: true
  defp valid_url?(_), do: false

  defp absinthe_ast(absinthe, file_path) do
    quote do
      @content GraphqlQuery.Schema.Absinthe.schema_from_absinthe!(unquote(absinthe))

      @impl GraphqlQuery.Schema
      def schema do
        gql [type: :schema, evaluate: true], @content
      end

      @impl GraphqlQuery.Schema
      def schema_path, do: unquote(file_path)
    end
  end
end
