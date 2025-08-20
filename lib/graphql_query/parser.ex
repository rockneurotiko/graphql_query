defmodule GraphqlQuery.Parser do
  @moduledoc """
  Utilities for parsing and analyzing GraphQL query strings.

  Provides functionality to detect dynamic parts in queries and format
  validation errors with proper location information.
  """

  @doc """
  Checks if a GraphQL query string contains dynamic interpolation parts.

  Returns `true` if the query contains `\#{` patterns, indicating dynamic
  content that cannot be validated at compile time.

  ## Examples

      iex> GraphqlQuery.Parser.has_dynamic_parts?("query { user { name } }")
      false

      iex> GraphqlQuery.Parser.has_dynamic_parts?("query { user { \#{@fields} } }")
      true

  """
  def has_dynamic_parts?(query) when is_binary(query) do
    # Check if the query contains any dynamic parts
    # Basic check now, because if it contains "\#{",
    # it means you were trying to use a dynamic part
    String.contains?(query, "\#{")
  end

  @doc """
  Formats a validation error with proper location information.

  Combines error location with warning location to provide accurate
  error positioning in the source file.

  ## Parameters

    * `error` - Validation error with message and location
    * `warn_location` - Source location information (line, column, file, etc.)
    * `prefix` - String prefix or function that generates error prefix

  ## Examples

      error = %GraphqlQuery.ValidationError{
        message: "Unused variable",
        locations: [%GraphqlQuery.Location{line: 2, column: 5}]
      }

      location = [line: 10, file: "query.ex"]
      formatted = GraphqlQuery.Parser.format_error(error, location, "Validation error:")

      # Returns: %{message: "[GraphqlQuery] Validation error: Unused variable", location: [...]}

  """
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

    file_path = warn_location[:file] || "unknown"
    error_prefix = error_prefix(prefix, location, file_path)

    msg = "[GraphqlQuery] #{error_prefix} #{error.message}"

    %{message: msg, location: location}
  end

  defp error_prefix(prefix, _loc, _file_path) when is_binary(prefix) do
    prefix
  end

  defp error_prefix(:runtime, loc, file_path) do
    "Runtime Validation error @ #{file_path}:#{loc[:line]}:#{loc[:column]} ->"
  end
end
