defmodule GraphqlQuery.Schema do
  @moduledoc """
  Behaviour and utilities for GraphQL schema management.

  Defines the contract for modules that provide GraphQL schemas and includes
  a `__using__` macro for easy schema module setup with automatic file loading
  and validation.

  ## Example

      defmodule MyApp.Schema do
        use GraphqlQuery.Schema, schema_path: "priv/schema.graphql"
      end

      # The schema will be automatically loaded from the file
      MyApp.Schema.schema()
      #=> "type Query { user(id: ID!): User } ..."

      # Get the file path
      MyApp.Schema.schema_path()
      #=> "priv/schema.graphql"

  """

  @callback schema() :: String.t()
  @callback schema_path() :: String.t()

  defstruct [:schema, :schema_path]

  defmacro __using__(opts) do
    file_path = Keyword.get(opts, :schema_path)

    quote do
      @behaviour GraphqlQuery.Schema

      use GraphqlQuery

      if unquote(file_path) do
        @impl GraphqlQuery.Schema
        def schema do
          gql_from_file(unquote(file_path), type: :schema)
        end

        @impl GraphqlQuery.Schema
        def schema_path, do: unquote(file_path)
      else
        @impl GraphqlQuery.Schema
        def schema_path, do: unquote(__CALLER__.file)
        defoverridable schema_path: 0
      end
    end
  end
end
