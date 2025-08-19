defmodule GraphqlQuery.Document do
  @moduledoc """
  Struct representation of a GraphQL query or mutation.
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
    name = signature(query)

    query =
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
      Fragment.from_query(query)
    else
      query
    end
  end

  defp signature(query) when is_binary(query) do
    query |> :erlang.phash2() |> Integer.to_string()
  end

  defp signature(_), do: nil

  def set_schema(query, schema), do: %{query | schema: schema}

  def add_variable(query, key, value), do: update_in(query.variables, &Map.put(&1, key, value))

  def add_variables(query, variables) when is_map(variables) do
    update_in(query.variables, &Map.merge(&1, variables))
  end

  def add_variables(query, [{k, _v} | _] = variables) when is_atom(k) do
    variables = keyword_to_map(variables)

    add_variables(query, variables)
  end

  defp keyword_to_map([{k, _v} | _] = variables) when is_atom(k) do
    Map.new(variables, fn {k, v} -> {k, keyword_to_map(v)} end)
  end

  defp keyword_to_map(variables), do: variables

  def add_fragment(query, %Fragment{} = fragment) do
    fragments = [fragment | query.fragments]
    %{query | fragments: unique_fragments(fragments)}
  end

  def add_fragments(query, [%Fragment{} | _] = fragments) do
    fragments = query.fragments ++ fragments
    %{query | fragments: fragments |> only_fragments() |> unique_fragments()}
  end

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
    def to_string(%GraphqlQuery.Document{} = gql_query) do
      GraphqlQuery.Document.format_query_with_fragments(gql_query)
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
        ", variables: ",
        Inspect.Map.inspect(gql_query.variables, opts),
        ", fragments: ",
        Inspect.List.inspect(fragments, opts),
        ">"
      ])
    end
  end
end
