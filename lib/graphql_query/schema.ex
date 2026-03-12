defmodule GraphqlQuery.Schema do
  @moduledoc """
  Behaviour and utilities for GraphQL schema management.

  Defines the contract for modules that provide GraphQL schemas and includes
  a `__using__` macro for easy schema module setup with automatic file loading
  and validation.

  Options for `use GraphqlQuery.Schema`:

    * `:schema_path` - Path to a `.graphql` or `.gql` schema file to load.
    * `:absinthe_schema` - An Absinthe schema module to extract the schema from.
    * `:federation` - Enable Apollo Federation directive support when loading the schema.

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

  defmacro __using__(opts) do
    file_path = Keyword.get(opts, :schema_path)
    absinthe = Keyword.get(opts, :absinthe_schema)
    federation = Keyword.get(opts, :federation, false)
    extra_opts = Keyword.drop(opts, [:schema_path, :absinthe_schema])

    quote do
      @behaviour GraphqlQuery.Schema

      use GraphqlQuery, unquote(extra_opts)

      def federation?, do: unquote(federation)

      cond do
        unquote(file_path) ->
          unquote(file_path_ast(file_path))

        unquote(absinthe) ->
          unquote(absinthe_ast(absinthe, __CALLER__.file))

        true ->
          @impl GraphqlQuery.Schema
          def schema_path, do: unquote(__CALLER__.file)
          defoverridable schema_path: 0
      end
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
