defmodule GraphqlQuery.Native do
  @moduledoc """
  Native interface to Rust functions for GraphQL query validation and formatting.
  """

  use Rustler,
    otp_app: :graphql_query,
    crate: "graphql_query_native"

  @doc """
  Validates a GraphQL query string with a document path.
  Returns :ok if valid, {:error, [String.t()]} if invalid with detailed error messages.
  """
  def validate_query(_query, _path), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Formats a GraphQL query string.
  Returns {:ok, formatted_query} or {:error, reason}.
  """
  def format_query(_query), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Validates and formats a GraphQL query string in one call.
  Returns {:ok, {validated_query, formatted_query}} or {:error, reason}.
  """
  def validate_and_format_query(_query), do: :erlang.nif_error(:nif_not_loaded)
end
