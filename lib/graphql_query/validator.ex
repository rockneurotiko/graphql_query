defmodule GraphqlQuery.Validator do
  @moduledoc """
  GraphQL query and schema validation.

  Provides validation functions for both GraphQL queries and schemas using
  the high-performance Rust-based native implementation. Supports schema-aware
  validation when a schema module is provided.
  """

  alias GraphqlQuery.{
    Document,
    DocumentInfo,
    Fragment,
    Native,
    SchemaInformation,
    ValidationWarning
  }

  @type document_type :: :query | :schema | :fragment
  @type document_info :: GraphqlQuery.DocumentInfo.t()
  @type validation_error :: GraphqlQuery.ValidationError.t()
  @type validation_warning :: ValidationWarning.t()

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

  @spec validate(Document.t()) ::
          :ok | {:ok, [validation_warning()]} | {:error, [validation_error()]}
  def validate(%Document{} = query) do
    path = query.path || "document.graphql"

    query
    |> to_string()
    |> validate(path, query.schema, query.type, federation: query.federation)
  end

  @spec validate(Fragment.t()) ::
          :ok | {:ok, [validation_warning()]} | {:error, [validation_error()]}
  def validate(%Fragment{} = fragment) do
    path = fragment.path || "document.graphql"

    fragment
    |> to_string()
    |> validate(path, fragment.schema, :fragment, federation: fragment.federation)
  end

  @doc """
  Extracts GraphQL document information.
  """
  @spec document_information(Document.t() | Fragment.t()) ::
          {:ok, DocumentInfo.t()} | {:error, [validation_error()]}
  def document_information(%Document{} = document) do
    path = document.path || "document.graphql"
    Native.document_information(document.query, path)
  end

  def document_information(%Fragment{} = fragment) do
    path = fragment.path || "fragment.graphql"
    Native.document_information(fragment.fragment, path)
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

  @spec validate(String.t(), String.t(), module() | nil, document_type(), keyword()) ::
          :ok | {:ok, [validation_warning()]} | {:error, [validation_error()]}
  def validate(query, path, schema_module, type, opts \\ [])

  def validate(query, path, _schema_module, :schema, opts)
      when is_binary(query) and is_binary(path) do
    federation = Keyword.get(opts, :federation, false)

    Native.validate_schema(query, path, federation)
    |> clean_result()
  end

  def validate(query, path, schema_module, :query, opts)
      when is_binary(query) and is_binary(path) do
    schema_info = build_schema_info(schema_module, opts)

    Native.validate_query(query, path, schema_info)
    |> clean_result()
  end

  def validate(query, path, schema_module, :fragment, opts)
      when is_binary(query) and is_binary(path) do
    schema_info = build_schema_info(schema_module, opts)

    Native.validate_fragment(query, path, schema_info)
    |> clean_result()
  end

  defp build_schema_info(nil, _opts), do: nil

  defp build_schema_info(schema_module, opts) do
    schema_doc = schema_module.schema()
    schema_federation = schema_doc.federation
    federation = Keyword.get(opts, :federation, false) || schema_federation

    %SchemaInformation{
      schema: to_string(schema_doc),
      path: schema_module.schema_path(),
      federation: federation,
      ignore_errors: schema_doc.ignore? || false
    }
  rescue
    GraphqlQuery.Schema.RemoteNotFetchedError -> nil
  end

  defp clean_result({:ok, []}), do: :ok
  defp clean_result({:ok, warnings}) when is_list(warnings), do: {:ok, warnings}
  defp clean_result(other), do: other

  @doc false
  def emit_validation_diagnostics(items, warn_location, prefix, document, item_to_ve_fn) do
    alias GraphqlQuery.Parser

    line_map = Parser.build_line_map(document)
    query_text = GraphqlQuery.extract_query_text(document)

    Enum.map(items, fn item ->
      ve = item_to_ve_fn.(item)
      ve = Parser.enrich_error_message(ve, query_text)
      {ve, frag_ctx} = GraphqlQuery.maybe_adjust_for_fragment(ve, line_map)
      formatted = Parser.format_error(ve, warn_location, prefix)
      message = GraphqlQuery.append_fragment_context(formatted.message, frag_ctx)
      {message, formatted.location}
    end)
  end
end
