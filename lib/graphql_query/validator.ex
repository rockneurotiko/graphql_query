defmodule GraphqlQuery.Validator do
  @moduledoc """
  GraphQL query and schema validation.

  Provides validation functions for both GraphQL queries and schemas using
  the high-performance Rust-based native implementation. Supports schema-aware
  validation when a schema module is provided.
  """
  alias GraphqlQuery.Native

  @type document_type :: :query | :schema | :fragment
  @type validation_error :: GraphqlQuery.ValidationError.t()

  @doc """
  Validates GraphQL documents.

  Accepts different input types:
  - String queries
  - GraphqlQuery.Document structs  
  - GraphqlQuery.Fragment structs

  Returns :ok if valid, {:error, [validation_error()]} if invalid with detailed error messages.

  ## Examples

  ### String query validation

      iex> GraphqlQuery.Validator.validate(~s|query GetUser($id: ID!) { user(id: $id) { name } }|)
      :ok

      iex> result = GraphqlQuery.Validator.validate("query T($unused: String) { field }")
      iex> match?({:error, [%GraphqlQuery.ValidationError{} | _]}, result)
      true

  ### Document struct validation

      iex> document = GraphqlQuery.Document.new("query GetUser { user { id } }")
      iex> GraphqlQuery.Validator.validate(document)
      :ok

      iex> schema_doc = GraphqlQuery.Document.new("type Query { field: String }", type: :schema)
      iex> GraphqlQuery.Validator.validate(schema_doc)
      :ok

  ### Fragment struct validation

      iex> fragment = GraphqlQuery.Document.new("fragment UserFields on User { id name }", name: "UserFields", type: :fragment)
      iex> GraphqlQuery.Validator.validate(fragment)
      :ok

  """
  @spec validate(String.t()) :: :ok | {:error, [validation_error()]}
  def validate(query) when is_binary(query) do
    validate(query, "document.graphql", nil, :query)
  end

  @spec validate(GraphqlQuery.Document.t()) :: :ok | {:error, [validation_error()]}
  def validate(%GraphqlQuery.Document{} = query) do
    path = query.path || "document.graphql"

    validate(to_string(query), path, query.schema, query.type)
  end

  @spec validate(GraphqlQuery.Fragment.t()) :: :ok | {:error, [validation_error()]}
  def validate(%GraphqlQuery.Fragment{} = query) do
    path = query.path || "document.graphql"

    validate(to_string(query), path, query.schema, :fragment)
  end

  @doc """
  Validates a GraphQL query string with a specific document path and optional schema.
  Returns :ok if valid, {:error, [validation_error()]} if invalid with detailed error messages.

  ## Examples

  ### Schema validation

      iex> schema = ~s|type Query { field: String }|
      iex> GraphqlQuery.Validator.validate(schema, "schema.graphql", nil, :schema)
      :ok

  ### Query validation without schema

      iex> query = ~s|query GetUser($id: ID!) { user(id: $id) { name } }|
      iex> GraphqlQuery.Validator.validate(query, "query.graphql", nil, :query)
      :ok

  ### Fragment validation without schema

      iex> fragment = ~s|fragment UserFields on User { id name email }|
      iex> GraphqlQuery.Validator.validate(fragment, "fragment.graphql", nil, :fragment)
      :ok

  ### Document struct validation

      iex> document = GraphqlQuery.Document.new("query GetUser { user { id } }")
      iex> GraphqlQuery.Validator.validate(document)
      :ok

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
    schema = if schema_module, do: to_string(schema_module.schema())
    schema_path = if schema_module, do: schema_module.schema_path()

    case Native.validate_query(query, path, schema, schema_path) do
      {:ok, _} -> :ok
      {:error, errors} -> {:error, errors}
    end
  end

  def validate(query, path, schema_module, :fragment)
      when is_binary(query) and is_binary(path) do
    schema = if schema_module, do: to_string(schema_module.schema())
    schema_path = if schema_module, do: schema_module.schema_path()

    case Native.validate_fragment(query, path, schema, schema_path) do
      {:ok, _} -> :ok
      {:error, errors} -> {:error, errors}
    end
  end
end
