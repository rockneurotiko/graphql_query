defmodule GraphqlQuery.Schema.Remote.Introspection do
  @moduledoc """
  Converts a GraphQL introspection query result into SDL (Schema Definition Language).

  Takes the JSON response from a standard introspection query and produces a
  `.graphql` SDL string that can be saved and loaded as a schema file.

  ## Supported Types

  All standard GraphQL type kinds are handled:

  - `SCALAR` — custom scalars (built-in scalars like `String`, `Int`, etc. are skipped)
  - `OBJECT` — object types with fields (introspection types prefixed with `__` are skipped)
  - `INPUT_OBJECT` — input types with input fields
  - `ENUM` — enum types with values (introspection enums prefixed with `__` are skipped)
  - `INTERFACE` — interface types with fields
  - `UNION` — union types with possible types
  - Directives — all directives including built-ins
  - Schema definition — emitted when root type names are non-standard

  Descriptions, deprecation annotations, and default values are preserved.
  """

  use GraphqlQuery

  @introspection_query ~GQL"""
  query IntrospectionQuery {
    __schema {
      description
      queryType {
        name
      }
      mutationType {
        name
      }
      subscriptionType {
        name
      }
      types {
        ...FullType
      }
      directives {
        name
        description
        locations
        isRepeatable
        args {
          ...InputValue
        }
      }
    }
  }

  fragment FullType on __Type {
    kind
    name
    description
    fields(includeDeprecated: true) {
      name
      description
      args {
        ...InputValue
      }
      type {
        ...TypeRef
      }
      isDeprecated
      deprecationReason
    }
    inputFields {
      ...InputValue
    }
    interfaces {
      ...TypeRef
    }
    enumValues(includeDeprecated: true) {
      name
      description
      isDeprecated
      deprecationReason
    }
    possibleTypes {
      ...TypeRef
    }
  }

  fragment InputValue on __InputValue {
    name
    description
    type {
      ...TypeRef
    }
    defaultValue
  }

  fragment TypeRef on __Type {
    kind
    name
    ofType {
      kind
      name
      ofType {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
                ofType {
                  kind
                  name
                }
              }
            }
          }
        }
      }
    }
  }
  """

  @doc """
  Returns the introspection document.

  This is the standard GraphQL introspection query including descriptions,
  subscription type, and directive repeatability.
  """
  @spec introspection_query() :: GraphqlQuery.Document.t()
  def introspection_query, do: @introspection_query

  @builtin_scalars ~w(String Int Float Boolean ID)

  @doc """
  Converts an introspection query result map to a GraphQL SDL string.

  Accepts either the full response `%{"data" => %{"__schema" => ...}}` or
  just the schema portion `%{"__schema" => ...}` or `%{"queryType" => ..., "types" => ...}`.

  Returns `{:ok, sdl}` on success or `{:error, reason}` on failure.

  ## Examples

      iex> result = %{"data" => %{"__schema" => %{"queryType" => %{"name" => "Query"}, "types" => [...], "directives" => [...]}}}
      iex> {:ok, sdl} = GraphqlQuery.Schema.Remote.Introspection.to_sdl(result)
      iex> String.contains?(sdl, "type Query")
      true

  """
  @spec to_sdl(map()) :: {:ok, String.t()} | {:error, String.t()}
  def to_sdl(%{"data" => %{"__schema" => schema}}), do: to_sdl_from_schema(schema)
  def to_sdl(%{"__schema" => schema}), do: to_sdl_from_schema(schema)
  def to_sdl(%{"queryType" => _} = schema), do: to_sdl_from_schema(schema)
  def to_sdl(%{"types" => _} = schema), do: to_sdl_from_schema(schema)

  def to_sdl(other) do
    {:error,
     "Invalid introspection result: expected a map with \"data\" or \"__schema\" key, got: #{inspect(Map.keys(other))}"}
  end

  defp to_sdl_from_schema(schema) do
    types = Map.get(schema, "types", [])
    directives = Map.get(schema, "directives", [])

    parts =
      []
      |> maybe_add_schema_def(schema)
      |> add_directives(directives)
      |> add_types(types)

    sdl = Enum.join(parts, "\n\n") <> "\n"
    {:ok, sdl}
  rescue
    e ->
      {:error, "Failed to convert introspection to SDL: #{Exception.message(e)}"}
  end

  # Schema definition — only emit if root type names are non-standard
  defp maybe_add_schema_def(parts, schema) do
    query_name = get_in(schema, ["queryType", "name"])
    mutation_name = get_in(schema, ["mutationType", "name"])
    subscription_name = get_in(schema, ["subscriptionType", "name"])

    if non_standard_root_types?(query_name, mutation_name, subscription_name) do
      fields =
        [
          if(query_name, do: "  query: #{query_name}"),
          if(mutation_name, do: "  mutation: #{mutation_name}"),
          if(subscription_name, do: "  subscription: #{subscription_name}")
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      [description_block(Map.get(schema, "description")) <> "schema {\n#{fields}\n}" | parts]
    else
      parts
    end
  end

  defp non_standard_root_types?(query_name, mutation_name, subscription_name) do
    (query_name != nil and query_name != "Query") or
      (mutation_name != nil and mutation_name != "Mutation") or
      (subscription_name != nil and subscription_name != "Subscription")
  end

  # Directives
  defp add_directives(parts, directives) do
    directive_sdls =
      directives
      |> Enum.sort_by(& &1["name"])
      |> Enum.map(&render_directive/1)

    parts ++ directive_sdls
  end

  defp render_directive(directive) do
    name = directive["name"]
    args = render_args(directive["args"] || [])
    locations = (directive["locations"] || []) |> Enum.join(" | ")

    repeatable = if directive["isRepeatable"], do: "repeatable ", else: ""

    description_block(directive["description"]) <>
      "directive @#{name}#{args} #{repeatable}on #{locations}"
  end

  # Types
  defp add_types(parts, types) do
    type_sdls =
      types
      |> Enum.reject(&introspection_type?/1)
      |> Enum.sort_by(fn t -> {type_sort_key(t["kind"]), t["name"]} end)
      |> Enum.map(&render_type/1)
      |> Enum.reject(&is_nil/1)

    parts ++ type_sdls
  end

  defp type_sort_key("SCALAR"), do: 0
  defp type_sort_key("ENUM"), do: 1
  defp type_sort_key("INTERFACE"), do: 2
  defp type_sort_key("UNION"), do: 3
  defp type_sort_key("OBJECT"), do: 4
  defp type_sort_key("INPUT_OBJECT"), do: 5
  defp type_sort_key(_), do: 6

  defp introspection_type?(%{"name" => "__" <> _}), do: true
  defp introspection_type?(_), do: false

  defp render_type(%{"kind" => "SCALAR", "name" => name} = type)
       when name not in @builtin_scalars do
    description_block(type["description"]) <> "scalar #{name}"
  end

  defp render_type(%{"kind" => "SCALAR", "name" => name}) when name in @builtin_scalars do
    nil
  end

  defp render_type(%{"kind" => "OBJECT"} = type) do
    name = type["name"]
    interfaces = type["interfaces"] || []

    implements =
      case interfaces do
        [] -> ""
        ifaces -> " implements " <> Enum.map_join(ifaces, " & ", &resolve_type_ref/1)
      end

    fields = render_fields(type["fields"] || [])

    description_block(type["description"]) <>
      "type #{name}#{implements} {\n#{fields}\n}"
  end

  defp render_type(%{"kind" => "INPUT_OBJECT"} = type) do
    name = type["name"]
    fields = render_input_fields(type["inputFields"] || [])

    description_block(type["description"]) <>
      "input #{name} {\n#{fields}\n}"
  end

  defp render_type(%{"kind" => "ENUM"} = type) do
    name = type["name"]
    values = render_enum_values(type["enumValues"] || [])

    description_block(type["description"]) <>
      "enum #{name} {\n#{values}\n}"
  end

  defp render_type(%{"kind" => "INTERFACE"} = type) do
    name = type["name"]
    fields = render_fields(type["fields"] || [])

    description_block(type["description"]) <>
      "interface #{name} {\n#{fields}\n}"
  end

  defp render_type(%{"kind" => "UNION"} = type) do
    name = type["name"]

    members =
      (type["possibleTypes"] || [])
      |> Enum.map_join(" | ", &resolve_type_ref/1)

    description_block(type["description"]) <>
      "union #{name} = #{members}"
  end

  defp render_type(_), do: nil

  # Fields (for OBJECT and INTERFACE)
  defp render_fields(fields) do
    fields
    |> Enum.map_join("\n", fn field ->
      name = field["name"]
      args = render_args(field["args"] || [])
      type_ref = resolve_type_ref(field["type"])
      deprecated = render_deprecated(field)

      indent(
        description_block(field["description"], "  ") <>
          "  #{name}#{args}: #{type_ref}#{deprecated}"
      )
    end)
  end

  # Input fields
  defp render_input_fields(fields) do
    fields
    |> Enum.map_join("\n", fn field ->
      name = field["name"]
      type_ref = resolve_type_ref(field["type"])
      default = render_default_value(field["defaultValue"])

      indent(description_block(field["description"], "  ") <> "  #{name}: #{type_ref}#{default}")
    end)
  end

  # Enum values
  defp render_enum_values(values) do
    values
    |> Enum.map_join("\n", fn value ->
      name = value["name"]
      deprecated = render_deprecated(value)

      indent(description_block(value["description"], "  ") <> "  #{name}#{deprecated}")
    end)
  end

  # Arguments
  defp render_args([]), do: ""

  defp render_args(args) do
    # Check if any arg has a description — if so, use multi-line format
    has_descriptions? = Enum.any?(args, fn a -> a["description"] not in [nil, ""] end)

    if has_descriptions? do
      rendered =
        args
        |> Enum.map_join("\n", fn arg ->
          name = arg["name"]
          type_ref = resolve_type_ref(arg["type"])
          default = render_default_value(arg["defaultValue"])

          indent(
            description_block(arg["description"], "    ") <> "    #{name}: #{type_ref}#{default}"
          )
        end)

      "(\n#{rendered}\n  )"
    else
      inner =
        args
        |> Enum.map_join(", ", fn arg ->
          name = arg["name"]
          type_ref = resolve_type_ref(arg["type"])
          default = render_default_value(arg["defaultValue"])

          "#{name}: #{type_ref}#{default}"
        end)

      "(#{inner})"
    end
  end

  # Type reference resolution — unwrap NON_NULL/LIST wrappers
  defp resolve_type_ref(%{"kind" => "NON_NULL", "ofType" => inner}) do
    resolve_type_ref(inner) <> "!"
  end

  defp resolve_type_ref(%{"kind" => "LIST", "ofType" => inner}) do
    "[" <> resolve_type_ref(inner) <> "]"
  end

  defp resolve_type_ref(%{"name" => name}) when is_binary(name) do
    name
  end

  defp resolve_type_ref(nil), do: "Unknown"

  # Deprecation
  defp render_deprecated(%{"isDeprecated" => true, "deprecationReason" => reason})
       when is_binary(reason) and reason != "" do
    " @deprecated(reason: \"#{escape_string_value(reason)}\")"
  end

  defp render_deprecated(%{"isDeprecated" => true}) do
    " @deprecated"
  end

  defp render_deprecated(_), do: ""

  # escape StringValue following spec at
  # https://spec.graphql.org/September2025/#sec-String)
  defp escape_string_value(reason) do
    reason
    |> String.to_charlist()
    |> Enum.map_join(&escape_codepoint/1)
  end

  defp escape_codepoint(?\\), do: "\\\\"
  defp escape_codepoint(?"), do: "\\\""
  defp escape_codepoint(?\b), do: "\\b"
  defp escape_codepoint(?\f), do: "\\f"
  defp escape_codepoint(?\n), do: "\\n"
  defp escape_codepoint(?\r), do: "\\r"
  defp escape_codepoint(?\t), do: "\\t"

  defp escape_codepoint(c) when c < 0x20 or (c >= 0x7F and c <= 0x9F) do
    "\\u" <> (c |> Integer.to_string(16) |> String.pad_leading(4, "0"))
  end

  defp escape_codepoint(c), do: <<c::utf8>>

  # Default values — stored as JSON-encoded strings in introspection
  defp render_default_value(nil), do: ""
  defp render_default_value(value), do: " = #{value}"

  # Description rendering
  defp description_block(description, prefix \\ "")
  defp description_block(nil, _prefix), do: ""
  defp description_block("", _prefix), do: ""

  defp description_block(desc, prefix) do
    desc = String.replace(desc, ~s("""), ~s(\\"""))

    if String.contains?(desc, "\n") or String.starts_with?(desc, "\"") or
         String.ends_with?(desc, "\"") or String.contains?(desc, ~s(""")) do
      "#{prefix}\"\"\"\n#{prefix}#{desc}\n#{prefix}\"\"\"\n"
    else
      "#{prefix}\"\"\"#{desc}\"\"\"\n"
    end
  end

  # Indent helper — ensures already indented description lines are not double-indented
  defp indent(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> line
    end)
  end
end
