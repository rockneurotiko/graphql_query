defmodule GraphqlQuery.Fragment do
  @moduledoc """
  Struct representation of a GraphQL fragment.
  """

  alias GraphqlQuery.{Document, DocumentInfo, Fragment, Signature}

  defstruct [:name, :fragment, :path, :schema, :document_info]

  @type t :: %__MODULE__{
          name: String.t(),
          fragment: String.t(),
          path: String.t() | nil,
          schema: module() | nil,
          document_info: DocumentInfo.t() | nil
        }

  @doc """
  Converts a GraphQL Document struct into a Fragment struct.

  Takes a Document that was created with `type: :fragment` and converts it
  to the appropriate Fragment representation.

  ## Examples

      iex> document = GraphqlQuery.Document.new("fragment UserData on User { id name }", name: "UserData", type: :query)
      iex> fragment = GraphqlQuery.Fragment.from_query(document)
      iex> fragment.name
      "UserData"
      iex> fragment.fragment
      "fragment UserData on User { id name }"

  """
  def from_query(%Document{} = document) do
    query = to_string(document)

    %__MODULE__{
      name: document.name,
      fragment: to_string(query),
      path: document.path,
      schema: document.schema
    }
  end

  @spec set_document_info(t(), DocumentInfo.t() | nil) :: t()
  def set_document_info(%__MODULE__{} = fragment, %DocumentInfo{} = document_info) do
    # If more than one fragments, warning?
    signature = Signature.signature(fragment)
    document_info = DocumentInfo.add_signature(document_info, signature)
    %{fragment | document_info: document_info}
  end

  def set_document_info(%__MODULE__{} = fragment, _) do
    %{fragment | document_info: nil}
  end

  defimpl String.Chars do
    def to_string(%Fragment{fragment: fragment}) do
      String.trim(fragment)
    end
  end
end
