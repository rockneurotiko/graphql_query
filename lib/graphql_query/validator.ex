defmodule GraphqlQuery.Validator do
  @moduledoc """
  GraphQL query and schema validation.

  Provides validation functions for both GraphQL queries and schemas using
  the high-performance Rust-based native implementation. Supports schema-aware
  validation when a schema module is provided.
  """

  alias GraphqlQuery.{Document, DocumentInfo, Fragment, Native, Signature}

  @type document_type :: :query | :schema | :fragment
  @type document_info :: GraphqlQuery.DocumentInfo.t()
  @type validation_error :: GraphqlQuery.ValidationError.t()

  @doc """
  Validates GraphQL documents.

  Accepts different input types:
  - GraphqlQuery.Document structs
  - GraphqlQuery.Fragment structs

  Returns {:ok, document} if valid, {:error, [validation_error()]} if invalid with detailed error messages.
  If the validation is correct, the document will have its `document_info` field populated with the document's signature and other metadata.

  ## Examples

  ### Document struct validation

      iex> document = GraphqlQuery.Document.new("query GetUser { user { id } }")
      iex> {:ok, updated_document} = GraphqlQuery.Validator.validate(document)
      iex> %GraphqlQuery.DocumentInfo{} = updated_document.document_info

      iex> schema_doc = GraphqlQuery.Document.new("type Query { field: String }", type: :schema)
      iex> {:ok, updated_schema} = GraphqlQuery.Validator.validate(schema_doc)
      iex> %GraphqlQuery.DocumentInfo{} = updated_schema.document_info

  ### Fragment struct validation

      iex> fragment = GraphqlQuery.Document.new("fragment UserFields on User { id name }", name: "UserFields", type: :fragment)
      iex> {:ok, updated_fragment} = GraphqlQuery.Validator.validate(fragment)
      iex> %GraphqlQuery.DocumentInfo{} = updated_fragment.document_info

  """

  @spec validate(Document.t()) ::
          {:ok, Document.t()} | {:error, [validation_error()]}
  def validate(%Document{} = query) do
    path = query.path || "document.graphql"

    query = maybe_add_document_info(query, path)

    case validate(to_string(query), path, query.schema, query.type) do
      :ok ->
        {:ok, query}

      error ->
        error
    end
  end

  @spec validate(Fragment.t()) ::
          {:ok, Fragment.t()} | {:error, [validation_error()]}
  def validate(%Fragment{} = query) do
    path = query.path || "document.graphql"

    query = maybe_add_document_info(query, path)

    case validate(to_string(query), path, query.schema, :fragment) do
      :ok ->
        {:ok, query}

      error ->
        error
    end
  end

  defp maybe_add_document_info(document, path) do
    if needs_document_info?(document) do
      add_document_info(document, path)
    else
      document
    end
  end

  defp add_document_info(document, path) do
    case document_information(document, path) do
      {:ok, info} ->
        Document.set_document_info(document, info)

      _error ->
        Document.set_document_info(document, nil)
    end
  end

  @doc """
  Extracts GraphQL document information.
  """
  @spec document_information(Document.t() | Fragment.t(), String.t() | nil) ::
          {:ok, DocumentInfo.t()} | {:error, [validation_error()]}
  def document_information(%Document{} = document, path) do
    Native.document_information(document.query, path)
  end

  def document_information(%Fragment{} = fragment, path) do
    Native.document_information(fragment.fragment, path)
  end

  defp needs_document_info?(%{document_info: nil}), do: true
  defp needs_document_info?(%{document_info: %{signature: nil}}), do: true

  defp needs_document_info?(%{document_info: %{signature: signature}} = document) do
    Signature.signature(document) != signature
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
      iex> {:ok, updated_document} = GraphqlQuery.Validator.validate(document)
      iex> %GraphqlQuery.DocumentInfo{} = updated_document.document_info

  """

  @spec validate(String.t(), String.t(), module() | nil, document_type()) ::
          :ok | {:error, [validation_error()]}
  def validate(query, path, _schema_module, :schema)
      when is_binary(query) and is_binary(path) do
    Native.validate_schema(query, path)
    |> clean_result()
  end

  def validate(query, path, schema_module, :query)
      when is_binary(query) and is_binary(path) do
    schema = if schema_module, do: to_string(schema_module.schema())
    schema_path = if schema_module, do: schema_module.schema_path()

    Native.validate_query(query, path, schema, schema_path)
    |> clean_result()
  end

  def validate(query, path, schema_module, :fragment)
      when is_binary(query) and is_binary(path) do
    schema = if schema_module, do: to_string(schema_module.schema())
    schema_path = if schema_module, do: schema_module.schema_path()

    Native.validate_fragment(query, path, schema, schema_path)
    |> clean_result()
  end

  defp clean_result({:ok, :ok}), do: :ok
  defp clean_result(other), do: other
end
