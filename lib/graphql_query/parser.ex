defmodule GraphqlQuery.Parser do
  def has_dynamic_parts?(query) when is_binary(query) do
    # Check if the query contains any dynamic parts
    # Basicy check now, because if it contains "\#{",
    # it means you were trying to use a dynamic part
    String.contains?(query, "\#{")
  end
end
