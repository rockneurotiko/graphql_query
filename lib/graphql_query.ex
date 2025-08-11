defmodule GraphqlQuery do
  @moduledoc """
  Elixir tools for validating and formatting GraphQL queries.

  This module provides a high-level API for GraphQL query processing,
  backed by a high-performance Rust implementation.
  """

  alias GraphqlQuery.Native

  @doc """
  Validates a GraphQL query string.
  Returns :ok if valid, {:error, [String.t()]} if invalid with detailed error messages.
  """
  @spec validate(String.t()) :: :ok | {:error, [String.t()]}
  def validate(query) when is_binary(query) do
    validate(query, "document.graphql")
  end

  @doc """
  Validates a GraphQL query string with a specific document path.
  Returns :ok if valid, {:error, [String.t()]} if invalid with detailed error messages.
  """
  @spec validate(String.t(), String.t()) :: :ok | {:error, [String.t()]}
  def validate(query, path) when is_binary(query) and is_binary(path) do
    case Native.validate_query(query, path) do
      {:ok, _} -> :ok
      {:error, errors} -> {:error, errors}
    end
  end

  @doc """
  Formats a GraphQL query string using the AST representation.
  Returns the original query if parsing fails.
  """
  @spec format(String.t()) :: String.t()
  def format(query) when is_binary(query) do
    Native.format_query(query)
  end

  @doc """
  GraphQL sigil that validates queries at compile time and prints warnings for any errors.

  Usage:
      import GraphqlQuery

      ~GQL\"\"\"
      query GetUser($id: ID!) {
        user(id: $id) {
          name
          email
        }
      }
      \"\"\"
  """
  defmacro sigil_GQL({:<<>>, meta, [query]}, _opts) do
    # Validate at compile time
    file = __CALLER__.file

    case validate(query, file) do
      :ok ->
        nil

      {:error, errors} ->
        error_strings = Enum.join(errors, "\n")

        warn_location = warn_location(meta, __CALLER__)

        IO.warn("GraphQL validation errors:\n#{error_strings}", warn_location)
    end

    # Return the query string
    query
  end

  defp warn_location(meta, %{line: line, file: file, function: function, module: module}) do
    column = if column = meta[:column], do: column + 2
    [line: line, function: function, module: module, file: file, column: column]
  end
end
