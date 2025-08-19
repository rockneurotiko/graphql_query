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
