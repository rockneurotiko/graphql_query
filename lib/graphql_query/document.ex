defmodule GraphqlQuery.Document do
  @moduledoc """
  Struct representation of a GraphQL query or mutation.

  If you need to build documents or fragments manually, you can use this methods.

  ## Example
        # Fragments
      iex> fragment = GraphqlQuery.Document.new("fragment UserFields on User { id name }", name: "UserFields", type: :fragment)
      iex> fragment.__struct__ == GraphqlQuery.Fragment
      true
      iex> fragment.name
      "UserFields"
      iex> fragment.name
      "UserFields"
      iex> fragment.fragment
      "fragment UserFields on User { id name }"

      # Queries
      iex> fragment = GraphqlQuery.Document.new("fragment UserFields on User { id name }", name: "UserFields", type: :fragment)
      iex> query = GraphqlQuery.Document.new("query { user { ...UserFields } }", fragments: [fragment])
      iex> query.query
      "query { user { ...UserFields } }"

      # Schemas
      iex> schema = GraphqlQuery.Document.new("schema { query: Query }", type: :schema)
      iex> schema.query
      "schema { query: Query }"
      iex> schema.type
      :schema

      # Manupilate the documents
      iex> query = GraphqlQuery.Document.new("query U(userId: ID!) { user(id: $userId) { ...UserFragment } }")
      iex> query = GraphqlQuery.Document.add_variable(query, :userId, 1)
      iex> query.variables
      %{userId: 1}
      iex> query = GraphqlQuery.Document.add_variables(query, [userId: 2, anotherVar: "test"])
      iex> query.variables
      %{userId: 2, anotherVar: "test"}
      iex> fragment = GraphqlQuery.Document.new("fragment UserFields on User { id name }", name: "UserFields", type: :fragment)
      iex> query = GraphqlQuery.Document.add_fragment(query, fragment)
      iex> query.fragments == [fragment]
      true
      iex> query = GraphqlQuery.Document.add_fragments(query, [fragment])
      iex> query.fragments == [fragment]
      true
      iex> query = GraphqlQuery.Document.set_schema(query, MyApp.Schema)
      iex> query.schema
      MyApp.Schema

      # Convert to string or encode as JSON
      iex> fragment = GraphqlQuery.Document.new("fragment UserFragment on User { id name }", name: "UserFragment", type: :fragment)
      iex> query = GraphqlQuery.Document.new("query User(userId: ID!) { user(id: $userId) { ...UserFragment } }", fragments: [fragment])
      iex> query = GraphqlQuery.Document.add_variable(query, :userId, 1)
      iex> to_string(query)   # String representation
      "query User(userId: ID!) { user(id: $userId) { ...UserFragment } }\\nfragment UserFragment on User { id name }"
      iex> query |> Jason.encode!() |> Jason.decode!()   # JSON encoding (works with Jason and JSON libraries)
      %{"query" => "query User(userId: ID!) { user(id: $userId) { ...UserFragment } }\\nfragment UserFragment on User { id name }", "variables" => %{"userId" => 1}}
  """

  alias GraphqlQuery.{DocumentInfo, Fragment, Signature, Validator}

  defstruct [
    :name,
    :query,
    :variables,
    :fragments,
    :schema,
    :path,
    :type,
    :document_info,
    :ignore?,
    :location
  ]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          query: String.t(),
          variables: map() | keyword(),
          fragments: list(Fragment.t()),
          schema: module() | nil,
          path: String.t() | nil,
          type: :query | :schema,
          document_info: DocumentInfo.t() | nil,
          ignore?: boolean(),
          location: keyword() | nil
        }

  @type document :: t() | Fragment.t()

  @type new_options :: [
          {:path, String.t() | nil},
          {:type, :query | :schema | :fragment},
          {:schema, module() | nil},
          {:fragments, list(Fragment.t())},
          {:name, String.t() | nil},
          {:ignore?, boolean() | nil},
          {:location, keyword() | nil}
        ]
  @spec new(String.t(), new_options()) :: document()
  @doc "Create a new GraphQL document or fragment from a document string and options."
  def new(query, opts \\ []) do
    path = Keyword.get(opts, :path, nil)
    type = Keyword.get(opts, :type, :query)
    schema = Keyword.get(opts, :schema, nil)
    fragments = Keyword.get(opts, :fragments, [])
    ignore? = Keyword.get(opts, :ignore?, false)
    location = Keyword.get(opts, :location, nil)

    # name = Keyword.get(opts, :name, Signature.signature(query))

    document =
      %__MODULE__{
        name: nil,
        query: query,
        variables: %{},
        fragments: fragments |> only_fragments() |> unique_fragments(),
        schema: schema,
        path: path,
        type: type,
        ignore?: ignore?,
        location: location
      }

    if type == :fragment do
      Fragment.from_query(document)
    else
      calculate_info(document)
    end
  end

  @doc "Set the name of the document"
  @spec set_name(t(), String.t() | nil) :: t()
  def set_name(document, name) when is_binary(name) do
    %{document | name: name}
  end

  def set_name(document, _) do
    %{document | name: nil}
  end

  @doc "Set schema to the document"
  @spec set_schema(t(), module()) :: t()
  def set_schema(document, schema), do: %{document | schema: schema}

  @doc "Add a variable to the document"
  @spec add_variable(t(), atom(), any()) :: t()
  def add_variable(document, key, value),
    do: update_in(document.variables, &Map.put(&1, key, value))

  @doc "Add multiple variables to the document"
  @spec add_variables(t(), map() | keyword()) :: t()
  def add_variables(document, variables) when is_map(variables) do
    update_in(document.variables, &Map.merge(&1, variables))
  end

  def add_variables(document, [{k, _v} | _] = variables) when is_atom(k) do
    variables = keyword_to_map(variables)

    add_variables(document, variables)
  end

  defp keyword_to_map([{k, _v} | _] = variables) when is_atom(k) do
    Map.new(variables, fn {k, v} -> {k, keyword_to_map(v)} end)
  end

  defp keyword_to_map(variables), do: variables

  @doc "Add a fragment to the document, if it's not a Fragment struct, it will be ignored."
  @spec add_fragment(t(), Fragment.t() | any()) :: t()
  def add_fragment(%__MODULE__{} = document, %Fragment{} = fragment) do
    fragments = [fragment | document.fragments]
    %{document | fragments: unique_fragments(fragments)}
  end

  def add_fragment(document, _), do: document

  @doc "Add multiple fragments to the document, if they are not Fragment structs, they will be ignored."
  @spec add_fragments(t(), list(Fragment.t() | any())) :: t()
  def add_fragments(%__MODULE__{} = document, []) do
    %{document | fragments: []}
  end

  def add_fragments(%__MODULE__{} = document, [%Fragment{} | _] = fragments) do
    fragments = document.fragments ++ fragments
    %{document | fragments: fragments |> only_fragments() |> unique_fragments()}
  end

  def add_fragments(document, _), do: document

  defp only_fragments(fragments) do
    Enum.filter(fragments, fn
      %Fragment{} ->
        true

      _ ->
        # credo:disable-for-next-line
        # TODO: Log warning?
        false
    end)
  end

  defp unique_fragments(fragments) do
    Enum.reduce(fragments, [], fn fragment, acc ->
      cond do
        fragment.name == nil ->
          [fragment | acc]

        Enum.any?(acc, &(&1.name == fragment.name)) ->
          acc

        true ->
          [fragment | acc]
      end
    end)
  end

  @spec calculate_info(document()) :: document()
  def calculate_info(document) do
    if needs_document_info?(document) do
      do_calculate_info(document)
    else
      document
    end
  end

  defp do_calculate_info(document) do
    case Validator.document_information(document) do
      {:ok, document_info} ->
        set_document_info(document, document_info)

      {:error, _errors} ->
        set_document_info(document, nil)
    end
  end

  defp needs_document_info?(%{document_info: nil}), do: true
  defp needs_document_info?(%{document_info: %{signature: nil}}), do: true

  defp needs_document_info?(%{document_info: %{signature: signature}} = document) do
    Signature.signature(document) != signature
  end

  @spec set_document_info(document(), DocumentInfo.t() | nil) :: t()
  def set_document_info(%__MODULE__{} = document, %DocumentInfo{} = document_info) do
    name = maybe_extract_unique_name(document_info) || document.name
    signature = Signature.signature(document)
    document_info = DocumentInfo.add_signature(document_info, signature)

    %{document | name: name, document_info: document_info}
  end

  def set_document_info(%Fragment{} = document, document_info) do
    Fragment.set_document_info(document, document_info)
  end

  def set_document_info(document, _), do: %{document | document_info: nil}

  defp maybe_extract_unique_name(%{queries: [query], mutations: [], subscriptions: []}) do
    query.name
  end

  defp maybe_extract_unique_name(%{queries: [], mutations: [mutation], subscriptions: []}) do
    mutation.name
  end

  defp maybe_extract_unique_name(%{queries: [], mutations: [], subscriptions: [subscription]}) do
    subscription.name
  end

  defp maybe_extract_unique_name(_), do: nil

  @doc "Format a query with its fragments into a single string."
  @spec format_query_with_fragments(t()) :: String.t()
  def format_query_with_fragments(%__MODULE__{query: query, fragments: fragments} = document) do
    fragments_string =
      fragments
      |> Enum.filter(&used_fragment?(&1, document))
      |> Enum.map_join("\n", &Kernel.to_string/1)
      |> String.trim()

    [String.trim(query), fragments_string]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp used_fragment?(_fragment, %{document_info: nil}), do: true

  defp used_fragment?(fragment, %{document_info: document_info}) do
    all_parts =
      document_info.queries ++
        document_info.mutations ++
        document_info.subscriptions ++
        document_info.fragments

    Enum.any?(all_parts, &fragment_used_in_part?(&1, fragment))
  end

  defp fragment_used_in_part?(%{fragments: used_fragments}, %{name: fragment_name}) do
    fragment_name in used_fragments
  end

  if Code.ensure_loaded?(JSON) do
    defimpl JSON.Encoder do
      @doc "Encode a GraphQL query document into JSON format."
      def encode(gql_query, encoder) do
        query = to_string(gql_query)
        kv = [query: query, variables: gql_query.variables]

        {io, _prefix} =
          Enum.flat_map_reduce(kv, ?{, fn {field, value}, prefix ->
            key =
              IO.iodata_to_binary([prefix, encoder.(Atom.to_string(field), encoder), ?:])

            {[key, encoder.(value, encoder)], ?,}
          end)

        io ++ [?}]
      end
    end
  end

  if Code.ensure_loaded?(Jason.Encoder) do
    defimpl Jason.Encoder do
      @doc "Encode a GraphQL query document into JSON format."
      def encode(gql_query, opts) do
        query = to_string(gql_query)
        kv = [query: query, variables: gql_query.variables]

        Jason.Encode.keyword(kv, opts)
      end
    end
  end

  # protocols implementation
  defimpl String.Chars do
    @doc "Convert a GraphQL query document to its string representation."
    def to_string(%GraphqlQuery.Document{} = gql_document) do
      GraphqlQuery.Document.format_query_with_fragments(gql_document)
    end
  end

  # defimpl Inspect do
  #   import Inspect.Algebra

  #   if Version.match?(System.version(), ">= 1.19.0-rc.0") do
  #     @doc "Inspect a GraphQL query document for debugging purposes."
  #     def inspect(gql_query, opts) do
  #       {name, opts} = to_doc_with_opts(gql_query.name, opts)

  #       {fragments, opts} = to_doc_with_opts(gql_query.fragments, opts)
  #       {query, opts} = to_doc_with_opts(gql_query.query, opts)
  #       {schema, opts} = to_doc_with_opts(gql_query.schema, opts)
  #       {variables, opts} = to_doc_with_opts(gql_query.variables, opts)

  #       {concat([
  #          "#GraphqlQuery.Document<name: ",
  #          name,
  #          ", query: ",
  #          query,
  #          ", schema: ",
  #          schema,
  #          ", variables: ",
  #          variables,
  #          ", fragments: ",
  #          fragments,
  #          ">"
  #        ]), opts}
  #     end
  #   else
  #     @doc "Inspect a GraphQL query document for debugging purposes."
  #     def inspect(gql_query, opts) do
  #       name =
  #         if gql_query.name,
  #           do: Inspect.BitString.inspect(gql_query.name, opts),
  #           else: Inspect.Atom.inspect(nil, opts)

  #       fragments = gql_query.fragments |> Enum.map(&to_string/1)

  #       concat([
  #         "#GraphqlQuery.Document<name: ",
  #         name,
  #         ", query: ",
  #         Inspect.BitString.inspect(gql_query.query, opts),
  #         ", schema: ",
  #         Inspect.Atom.inspect(gql_query.schema, opts),
  #         ", variables: ",
  #         Inspect.Map.inspect(gql_query.variables, opts),
  #         ", fragments: ",
  #         Inspect.List.inspect(fragments, opts),
  #         ">"
  #       ])
  #     end
  #   end
  # end
end
