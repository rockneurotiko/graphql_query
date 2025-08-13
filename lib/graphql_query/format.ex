defmodule GraphqlQuery.Format do
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
