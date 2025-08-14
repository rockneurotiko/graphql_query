defmodule GraphqlQuery.Parser do
  def has_dynamic_parts?(query) when is_binary(query) do
    # Check if the query contains any dynamic parts
    # Basicy check now, because if it contains "\#{",
    # it means you were trying to use a dynamic part
    String.contains?(query, "\#{")
  end

  def format_error(error, warn_location, prefix) do
    error_location =
      case error.locations do
        [] -> %{line: 0, column: 0}
        [location | _] -> location
      end

    warn_line = warn_location[:line] || 0
    warn_column = warn_location[:column] || 0

    new_location = [
      line: warn_line + error_location.line,
      column: warn_column + error_location.column
    ]

    location = Keyword.merge(warn_location, new_location)

    error_prefix = error_prefix(prefix, location)

    msg = "[GraphqlQuery] #{error_prefix} #{error.message}"

    %{message: msg, location: location}
  end

  defp error_prefix(prefix, _location) when is_binary(prefix) do
    prefix
  end

  defp error_prefix(prefix, location) when is_function(prefix, 1) do
    prefix.(location)
  end
end
