defmodule GraphqlQuery.Format do
  @moduledoc """
  GraphQL query and schema formatting functionality.

  Provides high-level formatting interface that delegates to the Rust-based
  native implementation for optimal performance. Formats GraphQL queries and schemas
  into a standardized, readable format.
  """
  alias GraphqlQuery.Native

  @doc """
  Formats a GraphQL query string using the AST representation.
  Returns the original query if parsing fails.
  """
  @spec format(String.t()) :: String.t()
  def format(query) when is_binary(query) do
    Native.format_query(query)
  end
end
