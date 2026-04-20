if Code.ensure_loaded?(Req) do
  defmodule GraphqlQuery.Schema.Remote.HttpClient do
    @moduledoc """
    HTTP client for fetching remote GraphQL schemas using Req.

    Builds a `%Req.Request{}`, optionally passes it through a schema module's
    `build_request/1` callback for customization (auth, headers, etc.), then
    executes it.

    ## Request Customization

    When a schema module is provided, its `build_request/1` function is called
    with the `%Req.Request{}` before execution. This allows adding authentication,
    custom headers, or any other request modifications.

    See `GraphqlQuery.Schema` for documentation on how to override `build_request/1`.
    """

    alias GraphqlQuery.Schema.Remote.Introspection

    @doc """
    Fetches content from a URL using HTTP GET.

    Optionally accepts a schema module whose `build_request/1` callback will be
    called to customize the request before sending.

    Returns `{:ok, body}` on success or `{:error, reason}` on failure.

    ## Examples

        iex> GraphqlQuery.Schema.Remote.HttpClient.fetch("https://example.com/schema.graphql")
        {:ok, "type Query { hello: String }"}

        iex> GraphqlQuery.Schema.Remote.HttpClient.fetch("https://example.com/schema.graphql", MyApp.Schema)
        {:ok, "type Query { hello: String }"}

    """
    @spec fetch(String.t(), module() | nil) :: {:ok, String.t()} | {:error, String.t()}
    def fetch(url, schema_module \\ nil) when is_binary(url) do
      req =
        Req.new(url: url, method: :get)
        |> apply_build_request(schema_module)

      case Req.request(req) do
        {:ok, %Req.Response{status: status, body: body}} when status >= 200 and status < 300 ->
          {:ok, body}

        {:ok, %Req.Response{status: status}} ->
          {:error, "HTTP #{status} when fetching #{url}"}

        {:error, reason} ->
          {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
      end
    rescue
      e ->
        {:error, "Failed to fetch #{url}: #{Exception.message(e)}"}
    end

    @doc """
    Fetches a schema via GraphQL introspection.

    Sends the standard introspection query as a POST request to the given URL,
    then converts the JSON response to SDL using `GraphqlQuery.Schema.Remote.Introspection`.

    Optionally accepts a schema module whose `build_request/1` callback will be
    called to customize the request before sending (e.g., for authentication).

    Returns `{:ok, sdl}` on success or `{:error, reason}` on failure.

    ## Examples

        iex> GraphqlQuery.Schema.Remote.HttpClient.introspect("https://api.example.com/graphql")
        {:ok, "type Query { ... }"}

        iex> GraphqlQuery.Schema.Remote.HttpClient.introspect("https://api.example.com/graphql", MyApp.Schema)
        {:ok, "type Query { ... }"}

    """
    @spec introspect(String.t(), module() | nil) :: {:ok, String.t()} | {:error, String.t()}
    def introspect(url, schema_module \\ nil) when is_binary(url) do
      req =
        Req.new(
          url: url,
          method: :post,
          json: Introspection.introspection_query()
        )
        |> apply_build_request(schema_module)

      case Req.request(req) do
        {:ok, %Req.Response{status: status, body: body}} when status >= 200 and status < 300 ->
          convert_introspection_response(body)

        {:ok, %Req.Response{status: status}} ->
          {:error, "HTTP #{status} when introspecting #{url}"}

        {:error, reason} ->
          {:error, "Failed to introspect #{url}: #{inspect(reason)}"}
      end
    rescue
      e ->
        {:error, "Failed to introspect #{url}: #{Exception.message(e)}"}
    end

    defp convert_introspection_response(body) when is_map(body) do
      case body do
        %{"errors" => errors} when is_list(errors) and errors != [] ->
          messages = Enum.map_join(errors, "; ", fn e -> e["message"] || inspect(e) end)
          {:error, "Introspection query returned errors: #{messages}"}

        _ ->
          Introspection.to_sdl(body)
      end
    end

    defp convert_introspection_response(body) when is_binary(body) do
      # Response wasn't auto-decoded as JSON — try manual decode
      case Jason.decode(body) do
        {:ok, decoded} -> convert_introspection_response(decoded)
        {:error, _} -> {:error, "Introspection response is not valid JSON"}
      end
    end

    defp convert_introspection_response(_body) do
      {:error, "Unexpected introspection response format"}
    end

    defp apply_build_request(req, nil), do: req

    defp apply_build_request(req, schema_module) when is_atom(schema_module) do
      if function_exported?(schema_module, :build_request, 1) do
        schema_module.build_request(req)
      else
        req
      end
    end
  end
end
