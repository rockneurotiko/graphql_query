defmodule GraphqlQuery.MacroOptions do
  @config_schema ignore: [
                   type: :boolean,
                   default: false,
                   required: false,
                   doc: "Ignore validation errors"
                 ],
                 type: [
                   type: :atom,
                   default: :query,
                   required: false,
                   doc: "Type of the GraphQL document, either :query or :schema"
                 ],
                 schema: [
                   type: :atom,
                   default: :not_set,
                   required: false,
                   doc: "Module that provides the GraphQL schema"
                 ],
                 evaluate: [
                   type: :boolean,
                   default: false,
                   required: false,
                   doc: "Try to evaluate dynamic parts of the document"
                 ],
                 runtime: [
                   type: :boolean,
                   default: false,
                   required: false,
                   doc: "Use runtime evaluation for the GraphQL query"
                 ],
                 fragments: [
                   type: {:list, :any},
                   default: [],
                   required: false,
                   doc: "List of fragments to include in the query"
                 ],
                 format: [
                   type: :boolean,
                   default: false,
                   required: false,
                   doc: "Apply formatting when converting to string"
                 ]

  @moduledoc """
  Options for the different macros in the GraphqlQuery module.

  • :ignore (boolean()) - Ignore validation errors The default value is false.

  • :type (:query | :schema | :fragment) - Type of the GraphQL document, either :query or
    :schema The default value is :query.

  • :schema (module()) - Module that provides the GraphQL schema The default value is
    nil.

  • :evaluate (boolean()) - Try to evaluate dynamic parts of the document The default
    value is false.

  • :runtime (boolean()) - Use runtime evaluation for the GraphQL query The default
    value is false.
  """

  defstruct Keyword.keys(@config_schema)

  @type t :: %__MODULE__{
          ignore: boolean() | nil,
          type: :query | :schema | :fragment,
          schema: module() | nil,
          evaluate: boolean() | nil,
          runtime: boolean() | nil,
          fragments: list(GraphqlQuery.Fragment.t()),
          format: boolean() | nil
        }

  @doc """
  Returns documentation string for available macro options.

  Provides detailed documentation for all configuration options
  that can be passed to GraphQL macros.

  ## Examples

      iex> docs = GraphqlQuery.MacroOptions.docs()
      iex> is_binary(docs)
      true

  """
  @spec docs() :: String.t()
  def docs do
    NimbleOptions.docs(@config_schema)
  end

  def to_keyword(%__MODULE__{} = opts) do
    Map.from_struct(opts)
    |> Enum.filter(fn {_k, v} -> not is_nil(v) end)
    |> Keyword.new()
  end

  @doc """
  Validates macro options against the schema.

  Validates and normalizes options for GraphQL macros, returning
  either a valid options struct or an error.

  ## Examples

      iex> {:ok, opts} = GraphqlQuery.MacroOptions.validate([type: :query, ignore: true])
      iex> opts.type
      :query
      iex> opts.ignore
      true

      iex> {:error, _reason} = GraphqlQuery.MacroOptions.validate([ignore: "invalid"])

  """
  @spec validate(Keyword.t()) :: {:ok, __MODULE__.t()} | {:error, term()}
  def validate(opts) do
    case NimbleOptions.validate(opts, @config_schema) do
      {:ok, opts} ->
        {:ok, struct(__MODULE__, opts)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validates macro options against the schema, raising on error.

  Like `validate/1` but raises an `ArgumentError` if validation fails.

  ## Examples

      iex> opts = GraphqlQuery.MacroOptions.validate!([type: :fragment])
      iex> opts.type
      :fragment

  """
  @spec validate!(Keyword.t()) :: __MODULE__.t() | no_return()
  def validate!(opts) do
    case validate(opts) do
      {:ok, validated_opts} -> validated_opts
      {:error, reason} -> raise ArgumentError, "Invalid options: #{inspect(reason)}"
    end
  end
end
