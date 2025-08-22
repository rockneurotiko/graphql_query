defmodule GraphqlQuery.Signature do
  @moduledoc """
  Generates unique signatures for GraphQL documents and fragments.

  This module provides functionality to create consistent hash-based signatures
  for GraphQL queries, mutations, subscriptions, and fragments. Signatures are
  useful for caching, deduplication, and tracking purposes.
  """

  alias GraphqlQuery.{Document, Fragment}

  @doc """
  Generates a signature for a GraphQL document or fragment.

  ## Parameters

    * `document` - Can be a `GraphqlQuery.Document` struct, `GraphqlQuery.Fragment` struct, or a binary string

  ## Returns

    * A string representation of the hash for valid inputs
    * `nil` for invalid or unsupported input types

  ## Examples

      iex> GraphqlQuery.Signature.signature("query { user { id } }")
      "123456789"

      iex> doc = %GraphqlQuery.Document{query: "mutation { createUser }"}
      iex> GraphqlQuery.Signature.signature(doc)
      "987654321"

      iex> GraphqlQuery.Signature.signature(nil)
      nil

  """
  @spec signature(Document.t() | Fragment.t() | binary() | any()) :: String.t() | nil
  def signature(%Document{query: query}), do: signature(query)
  def signature(%Fragment{fragment: fragment}), do: signature(fragment)

  def signature(document) when is_binary(document) do
    document |> :erlang.phash2() |> Integer.to_string()
  end

  def signature(_), do: nil
end
