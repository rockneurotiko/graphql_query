defmodule GraphqlQuery.Schema.Remote.IntrospectionSchemaEquivalenceTest do
  @moduledoc """
  Tests that the introspection JSON (test/fixtures/introspection.json) produces
  an SDL schema equivalent to the hand-downloaded schema
  (test/fixtures/introspection_schema.graphql).

  The introspection JSON includes extra metadata (directives, built-in scalars,
  introspection types) that the SDL file doesn't contain, so we compare the
  *user-defined* types, fields, arguments, and enum values between the two.
  """
  use ExUnit.Case, async: true

  alias GraphqlQuery.Schema.Remote.Introspection

  @introspection_json_path "test/fixtures/introspection.json"
  @schema_graphql_path "test/fixtures/introspection_schema.graphql"

  # ── Fixtures ──

  defp introspection_sdl do
    json = @introspection_json_path |> File.read!() |> Jason.decode!()
    {:ok, sdl} = Introspection.to_sdl(json)
    sdl
  end

  defp schema_graphql, do: File.read!(@schema_graphql_path)

  # ── SDL parsing helpers ──

  # Strip block-string descriptions so their contents aren't parsed as
  # type/field declarations by the regex helpers below.
  defp strip_block_strings(sdl) do
    Regex.replace(~r/"""[\s\S]*?"""/m, sdl, "")
  end

  defp extract_type_names(sdl, prefix) do
    sdl
    |> strip_block_strings()
    |> then(&Regex.scan(~r/^#{prefix}\s+(\w+)/m, &1))
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.sort()
  end

  defp extract_type_body(sdl, type_prefix, type_name) do
    sdl = strip_block_strings(sdl)
    pattern = ~r/^#{type_prefix}\s+#{Regex.escape(type_name)}\b/m

    case Regex.run(pattern, sdl, return: :index) do
      [{start_pos, _}] ->
        rest = binary_part(sdl, start_pos, byte_size(sdl) - start_pos)

        case :binary.match(rest, "{") do
          {open_pos, 1} ->
            after_open = binary_part(rest, open_pos + 1, byte_size(rest) - open_pos - 1)
            {:ok, find_matching_close(after_open, 1, <<>>)}

          :nomatch ->
            nil
        end

      _ ->
        nil
    end
  end

  defp find_matching_close(<<"{", rest::binary>>, depth, acc),
    do: find_matching_close(rest, depth + 1, <<acc::binary, "{">>)

  defp find_matching_close(<<"}", _::binary>>, 1, acc), do: acc

  defp find_matching_close(<<"}", rest::binary>>, depth, acc) when depth > 1,
    do: find_matching_close(rest, depth - 1, <<acc::binary, "}">>)

  defp find_matching_close(<<c, rest::binary>>, depth, acc),
    do: find_matching_close(rest, depth, <<acc::binary, c>>)

  defp find_matching_close(<<>>, _depth, acc), do: acc

  defp body_field_names({:ok, body}) do
    body
    |> strip_block_strings()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^(\w+)/, line) do
        [_, name] -> [name]
        _ -> []
      end
    end)
    |> Enum.sort()
  end

  defp body_field_names(nil), do: []

  # Returns a map of %{type_name => sorted_field_names} for all types of the given prefix
  defp all_type_fields(sdl, prefix) do
    extract_type_names(sdl, prefix)
    |> Map.new(fn name ->
      {name, sdl |> extract_type_body(prefix, name) |> body_field_names()}
    end)
  end

  # ── Tests ──

  describe "both schemas are individually valid" do
    test "introspection JSON converts to a valid GraphQL schema" do
      assert {:ok, _} =
               GraphqlQuery.Native.validate_schema(introspection_sdl(), "generated.graphql")
    end

    test "the hand-downloaded .graphql file is a valid GraphQL schema" do
      assert {:ok, _} = GraphqlQuery.Native.validate_schema(schema_graphql(), "original.graphql")
    end
  end

  describe "type names are equivalent" do
    test "same object, input, and enum type names" do
      sdl = introspection_sdl()
      schema = schema_graphql()

      for prefix <- ["type", "input", "enum"] do
        sdl_names = extract_type_names(sdl, prefix)
        schema_names = extract_type_names(schema, prefix)

        assert sdl_names == schema_names,
               "#{prefix} names differ.\n  SDL only: #{inspect(sdl_names -- schema_names)}\n  Schema only: #{inspect(schema_names -- sdl_names)}"
      end
    end
  end

  describe "fields are equivalent" do
    test "all object types have the same fields" do
      sdl = introspection_sdl()
      schema = schema_graphql()

      sdl_fields = all_type_fields(sdl, "type")
      schema_fields = all_type_fields(schema, "type")

      assert sdl_fields == schema_fields,
             "Object type fields differ:\n#{diff_maps(sdl_fields, schema_fields)}"
    end

    test "all input types have the same fields" do
      sdl = introspection_sdl()
      schema = schema_graphql()

      sdl_fields = all_type_fields(sdl, "input")
      schema_fields = all_type_fields(schema, "input")

      assert sdl_fields == schema_fields,
             "Input type fields differ:\n#{diff_maps(sdl_fields, schema_fields)}"
    end

    test "all enum types have the same values" do
      sdl = introspection_sdl()
      schema = schema_graphql()

      sdl_enums = all_type_fields(sdl, "enum")
      schema_enums = all_type_fields(schema, "enum")

      assert sdl_enums == schema_enums,
             "Enum values differ:\n#{diff_maps(sdl_enums, schema_enums)}"
    end
  end

  describe "key field signatures match" do
    # Each entry: {type_prefix, type_name, field_name, expected_args, expected_return_type}
    # nil args means the field takes no arguments.
    @field_signatures [
      # Scalar return types
      {"type", "Query", "_", nil, "Int"},
      {"type", "Album", "id", nil, "ID"},
      {"type", "Geo", "lat", nil, "Float"},
      {"type", "PageMetadata", "totalCount", nil, "Int"},
      # Object/list return types
      {"type", "Album", "user", nil, "User"},
      {"type", "PostsPage", "data", nil, "[Post]"},
      {"type", "PostsPage", "links", nil, "PaginationLinks"},
      # NON_NULL args
      {"type", "Query", "album", "id: ID!", "Album"},
      {"type", "Query", "user", "id: ID!", "User"},
      {"type", "Mutation", "deleteAlbum", "id: ID!", "Boolean"},
      {"type", "Mutation", "createAlbum", "input: CreateAlbumInput!", "Album"},
      # Optional args
      {"type", "Query", "albums", "options: PageQueryOptions", "AlbumsPage"},
      {"type", "User", "posts", "options: PageQueryOptions", "PostsPage"},
      # Input field types: required and optional
      {"input", "CreateAlbumInput", "title", nil, "String!"},
      {"input", "CreateAlbumInput", "userId", nil, "ID!"},
      {"input", "UpdateAlbumInput", "title", nil, "String"},
      {"input", "CreateUserInput", "address", nil, "AddressInput"},
      # List input fields
      {"input", "PageQueryOptions", "sort", nil, "[SortOptions]"},
      {"input", "PageQueryOptions", "operators", nil, "[OperatorOptions]"}
    ]

    test "field args and return types agree between SDL and .graphql" do
      sdl = introspection_sdl()
      schema = schema_graphql()

      failures =
        for {prefix, type_name, field, expected_args, expected_type} <- @field_signatures,
            reduce: [] do
          acc ->
            sdl_line = find_field_line(sdl, prefix, type_name, field)
            schema_line = find_field_line(schema, prefix, type_name, field)

            errors =
              []
              |> check_return_type(sdl_line, schema_line, expected_type, prefix, type_name, field)
              |> check_args(sdl_line, schema_line, expected_args, prefix, type_name, field)

            acc ++ errors
        end

      assert failures == [], Enum.join(failures, "\n")
    end
  end

  # ── Private helpers for the signature test ──

  defp find_field_line(sdl, type_prefix, type_name, field_name) do
    case extract_type_body(sdl, type_prefix, type_name) do
      {:ok, body} ->
        body
        |> strip_block_strings()
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.find(fn line ->
          match?([_, ^field_name], Regex.run(~r/^(\w+)/, line))
        end)

      _ ->
        nil
    end
  end

  defp field_return_type(nil), do: nil

  defp field_return_type(line) do
    stripped =
      case Regex.run(~r/^\w+\([^)]*\)(.*)$/, line) do
        [_, after_args] -> after_args
        _ -> String.replace(line, ~r/^\w+/, "")
      end

    case Regex.run(~r/^:\s*(.+)$/, String.trim(stripped)) do
      [_, type] -> String.trim(type)
      _ -> nil
    end
  end

  defp field_args(nil), do: nil

  defp field_args(line) do
    case Regex.run(~r/\(([^)]*)\)/, line) do
      [_, args] -> String.trim(args)
      _ -> nil
    end
  end

  defp check_return_type(errors, sdl_line, schema_line, expected, prefix, type_name, field) do
    sdl_type = field_return_type(sdl_line)
    schema_type = field_return_type(schema_line)

    cond do
      sdl_type != expected ->
        [
          "#{prefix} #{type_name}.#{field}: SDL return type #{inspect(sdl_type)}, expected #{inspect(expected)}"
          | errors
        ]

      schema_type != expected ->
        [
          "#{prefix} #{type_name}.#{field}: schema return type #{inspect(schema_type)}, expected #{inspect(expected)}"
          | errors
        ]

      true ->
        errors
    end
  end

  defp check_args(errors, sdl_line, schema_line, expected, prefix, type_name, field) do
    sdl_args = field_args(sdl_line)
    schema_args = field_args(schema_line)

    cond do
      sdl_args != expected ->
        [
          "#{prefix} #{type_name}.#{field}: SDL args #{inspect(sdl_args)}, expected #{inspect(expected)}"
          | errors
        ]

      schema_args != expected ->
        [
          "#{prefix} #{type_name}.#{field}: schema args #{inspect(schema_args)}, expected #{inspect(expected)}"
          | errors
        ]

      true ->
        errors
    end
  end

  defp diff_maps(sdl_map, schema_map) do
    all_keys = (Map.keys(sdl_map) ++ Map.keys(schema_map)) |> Enum.uniq() |> Enum.sort()

    all_keys
    |> Enum.flat_map(fn key ->
      sdl_val = Map.get(sdl_map, key)
      schema_val = Map.get(schema_map, key)

      if sdl_val != schema_val do
        ["  #{key}: SDL=#{inspect(sdl_val)}, schema=#{inspect(schema_val)}"]
      else
        []
      end
    end)
    |> Enum.join("\n")
  end
end
