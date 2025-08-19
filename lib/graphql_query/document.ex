defmodule GraphqlQuery.Document do
  @moduledoc """
  Struct representation of a GraphQL query or mutation.

  If you need to build documents or fragments manually, you can use this methods.

  ## Example
        # Fragments
      iex> fragment = GraphqlQuery.Document.new("fragment UserFields on User { id name }", name: "UserFields", type: :fragment)
      iex> fragment.name
      "UserFields"
      iex> fragment.query
      "fragment UserFields on User { id name }"
      iex> fragment.type
      :fragment

      # Queries
      iex> query = GraphqlQuery.Document.new("query { user { ...UserFields } }", fragments: [fragment])
      iex> query.query
      "query { user { ...UserFields } }"
      iex> query.type
      :query
      iex> to_string(query) # When conventing to string, it will include the fragments
      "query { user { ...UserFields } }\n\nfragment UserFields on User { id name }"

      # Schemas
      iex> schema = GraphqlQuery.Document.new("schema { query: Query }", type: :schema)
      iex> schema.query
      "schema { query: Query }"
      iex> schema.type
      :schema

      # Manupilate the documents
      iex> query = GraphqlQuery.Document.add_variable(query, :userId, 1)
      iex> query.variables
      %{userId: 1}

      iex> query = GraphqlQuery.Document.add_variables(query, [userId: 2, anotherVar: "test"])
      iex> query.variables
      %{userId: 2, anotherVar: "test"}

      iex> query = GraphqlQuery.Document.add_fragment(query, fragment)
      iex> query.fragments
      [%GraphqlQuery.Fragment{name: "UserFields", fragment: "fragment UserFields on User { id name }"}]

      iex> query = GraphqlQuery.Document.add_fragments(query, [fragment])
      iex> query.fragments
      [%GraphqlQuery.Fragment{name: "UserFields", fragment: "fragment UserFields on User { id name }"}]

      iex> query = GraphqlQuery.Document.set_schema(query, MyApp.Schema)
      iex> query.schema
      MyApp.Schema

      # Convert to string will include the fragments
      iex> to_string(query)
      "query { user { ...UserFields } }\n\nfragment UserFields on User { id name }"

      # JSON encoding (works with Jason and JSON libraries)
      iex> Jason.encode!(query)
      "{\"query\":\"query { user { ...UserFields } }\n\nfragment UserFields on User { id name }\",\"variables\":{\"userId\":2,\"anotherVar\":\"test\"}}"


  """
  alias GraphqlQuery.Fragment

  defstruct [:name, :query, :variables, :fragments, :schema, :path, :type]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          query: String.t(),
          variables: map() | keyword(),
          fragments: list(Fragment.t()),
          schema: module() | nil,
          path: String.t() | nil,
          type: :query | :schema
        }

  @spec new(String.t(), keyword()) :: t() | Fragment.t()
  def new(query, opts \\ []) do
    path = Keyword.get(opts, :path, nil)
    type = Keyword.get(opts, :type, :query)
    schema = Keyword.get(opts, :schema, nil)
    fragments = Keyword.get(opts, :fragments, [])

    # TODO: Parsing the query shall return the name of the query/fragment
    name = Keyword.get(opts, :name, signature(query))

    document =
      %__MODULE__{
        name: name,
        query: query,
        variables: %{},
        fragments: fragments |> only_fragments() |> unique_fragments(),
        schema: schema,
        path: path,
        type: type
      }

    if type == :fragment do
      Fragment.from_query(document)
    else
      document
    end
  end

  defp signature(document) when is_binary(document) do
    document |> :erlang.phash2() |> Integer.to_string()
  end

  defp signature(_), do: nil

  def set_schema(document, schema), do: %{document | schema: schema}

  def add_variable(document, key, value),
    do: update_in(document.variables, &Map.put(&1, key, value))

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

  def add_fragment(%__MODULE__{} = document, %Fragment{} = fragment) do
    fragments = [fragment | document.fragments]
    %{document | fragments: unique_fragments(fragments)}
  end

  def add_fragment(document, _), do: document

  def add_fragments(%__MODULE__{} = document, []) do
    %{document | fragments: []}
  end

  def add_fragments(%__MODULE__{} = document, [%Fragment{} | _] = fragments) do
    fragments = document.fragments ++ fragments
    %{document | fragments: fragments |> only_fragments() |> unique_fragments()}
  end

  def add_fragments(document, _), do: document

  def only_fragments(fragments) do
    Enum.filter(fragments, fn
      %Fragment{} ->
        true

      _ ->
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

  def format_query_with_fragments(%__MODULE__{query: query, fragments: fragments}) do
    fragments_string = fragments |> Enum.map_join("\n", &Kernel.to_string/1) |> String.trim()

    [String.trim(query), fragments_string]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  if Code.ensure_loaded?(JSON) do
    defimpl JSON.Encoder do
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
      def encode(gql_query, opts) do
        query = to_string(gql_query)
        kv = [query: query, variables: gql_query.variables]

        Jason.Encode.keyword(kv, opts)
      end
    end
  end

  # protocols implementation
  defimpl String.Chars do
    def to_string(%GraphqlQuery.Document{} = gql_document) do
      GraphqlQuery.Document.format_query_with_fragments(gql_document)
    end
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(gql_query, opts) do
      name =
        if gql_query.name,
          do: Inspect.BitString.inspect(gql_query.name, opts),
          else: Inspect.Atom.inspect(nil, opts)

      fragments = gql_query.fragments |> Enum.map(&to_string/1)

      concat([
        "#GraphqlQuery.Document<name: ",
        name,
        ", query: ",
        Inspect.BitString.inspect(gql_query.query, opts),
        ", schema: ",
        Inspect.Atom.inspect(gql_query.schema, opts),
        ", variables: ",
        Inspect.Map.inspect(gql_query.variables, opts),
        ", fragments: ",
        Inspect.List.inspect(fragments, opts),
        ">"
      ])
    end
  end
end
