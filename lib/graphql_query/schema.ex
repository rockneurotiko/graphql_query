defmodule GraphqlQuery.Schema do
  @moduledoc """

  """

  @callback schema() :: String.t()
  @callback schema_path() :: String.t()

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
      end
    end
  end
end
