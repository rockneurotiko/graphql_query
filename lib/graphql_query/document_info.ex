defmodule GraphqlQuery.DocumentInfo do
  @moduledoc """
  Represents the structured information about a raw GraphQL document.

  This struct contains all the parsed components of a GraphQL document,
  including queries, mutations, subscriptions, fragments, and an optional signature
  for document identification and caching purposes.
  """

  alias GraphqlQuery.{FragmentInfo, MutationInfo, QueryInfo, SubscriptionInfo}

  defstruct [:queries, :mutations, :fragments, :subscriptions, :signature]

  @type t :: %__MODULE__{
          queries: [QueryInfo.t()],
          mutations: [MutationInfo.t()],
          fragments: [FragmentInfo.t()],
          subscriptions: [SubscriptionInfo.t()],
          signature: String.t() | nil
        }

  @doc """
  Adds or updates the signature field of a DocumentInfo struct.

  ## Parameters

    * `doc_info` - A DocumentInfo struct
    * `signature` - A string signature or nil to clear the signature

  ## Returns

    * Updated DocumentInfo struct with the new signature

  ## Examples

      iex> info = %GraphqlQuery.DocumentInfo{queries: [], mutations: [], fragments: [], subscriptions: [], signature: nil}
      iex> GraphqlQuery.DocumentInfo.add_signature(info, "abc123")
      %GraphqlQuery.DocumentInfo{queries: [], mutations: [], fragments: [], subscriptions: [], signature: "abc123"}

  """
  @spec add_signature(t(), String.t() | nil) :: t()
  def add_signature(%__MODULE__{} = doc_info, signature) do
    %{doc_info | signature: signature}
  end
end
