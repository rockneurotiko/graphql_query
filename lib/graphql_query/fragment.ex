defmodule GraphqlQuery.Fragment do
  @moduledoc """
  Struct representation of a GraphQL fragment.
  """

  defstruct [:name, :fragment, :path, :schema]

  @type t :: %__MODULE__{
          name: String.t(),
          fragment: String.t(),
          path: String.t() | nil,
          schema: module() | nil
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
  def from_query(%GraphqlQuery.Document{} = document) do
    query = to_string(document)

    %__MODULE__{
      name: document.name,
      fragment: to_string(query),
      path: document.path,
      schema: document.schema
    }
  end

  defimpl String.Chars do
    def to_string(%GraphqlQuery.Fragment{fragment: fragment}) do
      String.trim(fragment)
    end
  end
end
