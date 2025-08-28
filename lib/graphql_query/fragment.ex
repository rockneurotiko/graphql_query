defmodule GraphqlQuery.Fragment do
  @moduledoc """
  Struct representation of a GraphQL fragment.
  """

  alias GraphqlQuery.{Document, DocumentInfo, Fragment, Signature}

  require GraphqlQuery.Logger

  defstruct [:name, :fragment, :path, :schema, :document_info, :ignore?, :location, :format]

  @type t :: %__MODULE__{
          name: String.t(),
          fragment: String.t(),
          path: String.t() | nil,
          schema: module() | nil,
          document_info: DocumentInfo.t() | nil,
          ignore?: boolean(),
          location: keyword() | nil,
          format: boolean()
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

    fragment = %__MODULE__{
      name: document.name,
      fragment: to_string(query),
      path: document.path,
      schema: document.schema,
      ignore?: document.ignore?,
      location: document.location,
      format: document.format
    }

    Document.calculate_info(fragment)
  end

  @spec set_document_info(t(), DocumentInfo.t() | nil) :: t()
  def set_document_info(%__MODULE__{} = fragment, %DocumentInfo{} = document_info) do
    # If more than one fragments, warning?
    name = extract_name(fragment, document_info)
    signature = Signature.signature(fragment)
    document_info = DocumentInfo.add_signature(document_info, signature)
    %{fragment | name: name, document_info: document_info}
  end

  def set_document_info(%__MODULE__{} = fragment, _) do
    %{fragment | name: nil, document_info: nil}
  end

  defp extract_name(document, %{fragments: fragments}) do
    case fragments do
      [fragment] ->
        fragment.name

      [fragment | _] ->
        msg = """
        More than one fragment found in the fragment definition. Using #{fragment.name} as the fragment name for lookup.
        It is recommended to declare every fragment independently.
        """

        maybe_warning(document, msg)
        fragment.name

      _fragments ->
        msg = """
        No fragments found in the fragment definition. Unable to extract a name for the fragment.
        """

        maybe_warning(document, msg)

        nil
    end
  end

  defp maybe_warning(%{ignore?: true}, _), do: :ok

  defp maybe_warning(%{location: location}, message) do
    GraphqlQuery.Logger.warning(message, location)
  end

  defimpl String.Chars do
    def to_string(%Fragment{fragment: fragment, format: true}) do
      content = String.trim(fragment)
      GraphqlQuery.Format.format(content)
    end

    def to_string(%Fragment{fragment: fragment}) do
      String.trim(fragment)
    end
  end
end
