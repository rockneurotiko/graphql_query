defmodule GraphqlQuery.Format do
  @moduledoc """
  GraphQL document and schema formatting functionality.

  Provides high-level formatting interface that delegates to the Rust-based
  native implementation for optimal performance. Formats GraphQL queries and schemas
  into a standardized, readable format.

  Example:

      iex> GraphqlQuery.Format.format("query { user { id name } }")
      "{\\n  user {\\n    id\\n    name\\n  }\\n}\\n"
  """
  alias GraphqlQuery.Native

  @doc """
  Formats a GraphQL document string using the AST representation.
  Returns the original document if parsing fails.
  """
  @spec format(String.t()) :: String.t()
  def format(query) when is_binary(query) do
    Native.format_query(query)
  end
end
