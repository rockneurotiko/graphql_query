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
  def format_error(%GraphqlQuery.ValidationError{} = error, warn_location, prefix) do
    location = error_location(error, warn_location)

    file_path = warn_location[:file] || "unknown"
    error_prefix = error_prefix(prefix, location, file_path)

    msg = "[GraphqlQuery] #{error_prefix} #{error.message}"

    %{message: msg, location: location}
  end

  def format_error(error, location, prefix) when is_binary(error) do
    file_path = location[:file] || "unknown"
    error_prefix = error_prefix(prefix, location, file_path)

    "[GraphqlQuery] #{error_prefix} #{error}"
  end

  defp error_location(error, warn_location) do
    error_location =
      case error.locations do
        [] -> %{line: 0, column: 0}
        [location | _] -> location
      end

    warn_line = warn_location[:line] || 0
    indentation = warn_location[:indentation] || 0

    # warn_location[:column] || 0
    warn_column = indentation

    new_location = [
      line: warn_line + error_location.line,
      column: warn_column + error_location.column
    ]

    Keyword.merge(warn_location, new_location)
  end

  @doc """
  Builds a line map for a document with its fragments.

  Returns a map with:
  - `:segments` — list of `{source, start_line, end_line}` tuples where source is
    either `:query` or `{:fragment, name}`. Lines are 1-indexed and refer to
    positions in the combined validation string (query + appended fragments).
  - `:spreads` — map of `%{fragment_name => line_in_query}` indicating where each
    fragment spread (`...FragmentName`) appears in the query text.
  """
  def build_line_map(%GraphqlQuery.Document{} = document) do
    query_text = String.trim(document.query)
    query_lines = count_lines(query_text)

    # Get the used fragments in the same order as format_query_with_fragments
    used_fragments = used_fragments_for(document)

    # Build segments: query occupies lines 1..query_lines
    initial = [{:query, 1, query_lines}]

    {segments, _} =
      Enum.reduce(used_fragments, {initial, query_lines}, fn fragment, {acc, offset} ->
        frag_text = Kernel.to_string(fragment)
        frag_lines = count_lines(frag_text)
        start = offset + 1
        finish = offset + frag_lines
        name = fragment.name || "unnamed"
        {acc ++ [{{:fragment, name}, start, finish}], finish}
      end)

    # Build spread locations: find `...FragmentName` in the query text
    spreads = find_spread_lines(query_text)

    %{segments: segments, spreads: spreads}
  end

  def build_line_map(_), do: %{segments: [], spreads: %{}}

  @doc """
  Resolves which source (query or fragment) an error line belongs to.

  Returns `{:query, relative_line}` or `{:fragment, name, relative_line}`.
  """
  def resolve_error_source(error_line, %{segments: segments}) do
    resolve_error_source(error_line, segments)
  end

  def resolve_error_source(error_line, segments) when is_list(segments) do
    Enum.find_value(segments, {:query, error_line}, fn
      {:query, start, finish} when error_line >= start and error_line <= finish ->
        {:query, error_line - start + 1}

      {{:fragment, name}, start, finish} when error_line >= start and error_line <= finish ->
        {:fragment, name, error_line - start + 1}

      _ ->
        nil
    end)
  end

  @doc """
  Finds the line in the query where a fragment spread (`...FragmentName`) appears.

  Returns the line number (1-indexed) or `nil` if the spread is not found.
  """
  def find_spread_line(%{spreads: spreads}, fragment_name) do
    Map.get(spreads, fragment_name)
  end

  def find_spread_line(_, _), do: nil

  defp find_spread_lines(query_text) do
    query_text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce(%{}, &collect_spread_names/2)
  end

  defp collect_spread_names({line, line_num}, acc) do
    case Regex.scan(~r/\.\.\.\s*(\w+)/, line) do
      [] ->
        acc

      matches ->
        Enum.reduce(matches, acc, fn [_, name], inner_acc ->
          Map.put_new(inner_acc, name, line_num)
        end)
    end
  end

  defp used_fragments_for(%GraphqlQuery.Document{fragments: fragments} = document) do
    GraphqlQuery.Document.filter_used_fragments_public(document, fragments)
  end

  defp count_lines(text) do
    text |> String.split("\n") |> length()
  end

  defp error_prefix(prefix, _loc, _file_path) when is_binary(prefix) do
    prefix
  end

  defp error_prefix(:runtime, loc, file_path) do
    "Runtime Validation error @ #{file_path}:#{loc[:line]}:#{loc[:column]} ->"
  end

  # Pattern for apollo-compiler's UnsupportedValueType with a variable
  @found_variable_pattern ~r/^expected value of type (.+), found a variable$/

  @doc """
  Enriches validation error messages that lack detail.

  Apollo-compiler's `UnsupportedValueType` diagnostic produces messages like
  `"expected value of type ID, found a variable"` without naming the variable
  or its declared type. This function detects that pattern and enhances the
  message using the query text and error location.
  """
  def enrich_error_message(
        %GraphqlQuery.ValidationError{message: message, locations: [loc | _]} = error,
        query_text
      )
      when is_binary(query_text) do
    case Regex.run(@found_variable_pattern, message) do
      [_, expected_type] ->
        with var_name when is_binary(var_name) <-
               extract_variable_at(query_text, loc.line, loc.column),
             var_type when is_binary(var_type) <- find_variable_type(query_text, var_name) do
          enriched =
            "expected value of type #{expected_type}, found variable `$#{var_name}` of type `#{var_type}`"

          %{error | message: enriched}
        else
          _ -> error
        end

      _ ->
        error
    end
  end

  def enrich_error_message(error, _query_text), do: error

  # Extracts the variable name (without $) at the given line/column in the query text.
  defp extract_variable_at(query_text, line, column) do
    query_text
    |> String.split("\n")
    |> Enum.at(line - 1)
    |> case do
      nil ->
        nil

      source_line ->
        # column is 1-indexed; extract from that position onwards
        rest = String.slice(source_line, max(column - 1, 0)..-1//1)

        case Regex.run(~r/^\$([a-zA-Z_]\w*)/, rest) do
          [_, name] -> name
          _ -> nil
        end
    end
  end

  # Finds the declared type of a variable by scanning operation definitions.
  # Looks for patterns like `$name: Type` or `$name: Type!` or `$name: [Type!]!`
  defp find_variable_type(query_text, var_name) do
    # Match $var_name followed by : and its type annotation.
    # The type can include [], !, and nested combinations.
    # We capture up to the next comma, closing paren, or equals sign (default value).
    pattern = Regex.compile!("\\$" <> Regex.escape(var_name) <> "\\s*:\\s*([^,)=]+)")

    case Regex.run(pattern, query_text) do
      [_, type_str] -> String.trim(type_str)
      _ -> nil
    end
  end
end
