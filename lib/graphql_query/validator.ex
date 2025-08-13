defmodule GraphqlQuery.Validator do
  alias GraphqlQuery.Native

  @doc """
  Validates a GraphQL query string.
  Returns :ok if valid, {:error, [String.t()]} if invalid with detailed error messages.
  """
  @spec validate(String.t()) :: :ok | {:error, [String.t()]}
  def validate(query) when is_binary(query) do
    validate(query, "document.graphql")
  end

  @doc """
  Validates a GraphQL query string with a specific document path.
  Returns :ok if valid, {:error, [String.t()]} if invalid with detailed error messages.
  """
  @spec validate(String.t(), String.t()) :: :ok | {:error, [String.t()]}
  def validate(query, path) when is_binary(query) and is_binary(path) do
    case Native.validate_query(query, path) do
      {:ok, _} -> :ok
      {:error, errors} -> {:error, errors}
    end
  end
end
