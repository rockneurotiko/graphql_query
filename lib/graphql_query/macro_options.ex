defmodule GraphqlQuery.MacroOptions do
  @config_schema ignore: [
                   type: {:or, [:boolean, nil]},
                   default: nil,
                   doc: "Ignore validation errors"
                 ],
                 type: [
                   type: :atom,
                   default: :query,
                   doc: "Type of the GraphQL document, either :query or :schema"
                 ],
                 schema: [
                   type: :any,
                   default: :not_set,
                   doc: "Module that provides the GraphQL schema"
                 ],
                 evaluate: [
                   type: {:or, [:boolean, nil]},
                   default: nil,
                   doc: "Try to evaluate dynamic parts of the document"
                 ],
                 runtime: [
                   type: {:or, [:boolean, nil]},
                   default: nil,
                   doc: "Use runtime evaluation for the GraphQL query"
                 ],
                 fragments: [
                   type: {:list, :any},
                   default: [],
                   doc: "List of fragments to include in the query"
                 ]

  @moduledoc """
  Options for the `gql` macro.


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
          fragments: list(GraphqlQuery.Fragment.t())
        }

  @spec docs() :: String.t()
  def docs do
    NimbleOptions.docs(@config_schema)
  end

  @spec validate(Keyword.t()) :: {:ok, __MODULE__.t()} | {:error, term()}
  def validate(opts) do
    case NimbleOptions.validate(opts, @config_schema) do
      {:ok, opts} ->
        {:ok, struct(__MODULE__, opts)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec validate!(Keyword.t()) :: __MODULE__.t() | no_return()
  def validate!(opts) do
    case validate(opts) do
      {:ok, validated_opts} -> validated_opts
      {:error, reason} -> raise ArgumentError, "Invalid options: #{inspect(reason)}"
    end
  end
end
