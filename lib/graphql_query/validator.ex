defmodule GraphqlQuery.Validator do
  alias GraphqlQuery.Native

  @type document_type :: :query | :schema
  @type validation_error :: GraphqlQuery.Native.ValidationError.t()

  @doc """
  Validates a GraphQL query string.
  Returns :ok if valid, {:error, [String.t()]} if invalid with detailed error messages.
  """
  @spec validate(String.t()) :: :ok | {:error, [validation_error()]}
  def validate(query) when is_binary(query) do
    validate(query, "document.graphql", nil, :query)
  end

  @doc """
  Validates a GraphQL query string with a specific document path.
  Returns :ok if valid, {:error, [String.t()]} if invalid with detailed error messages.
  """

  @spec validate(String.t(), String.t(), module() | nil, document_type()) ::
          :ok | {:error, [validation_error()]}
  def validate(query, path, _schema_module, :schema)
      when is_binary(query) and is_binary(path) do
    case Native.validate_schema(query, path) do
      {:ok, _} -> :ok
      {:error, errors} -> {:error, errors}
    end
  end

  def validate(query, path, schema_module, :query)
      when is_binary(query) and is_binary(path) do
    schema = if schema_module, do: schema_module.schema()
    schema_path = if schema_module, do: schema_module.schema_path()

    case Native.validate_query(query, path, schema, schema_path) do
      {:ok, _} -> :ok
      {:error, errors} -> {:error, errors}
    end
  end
end
