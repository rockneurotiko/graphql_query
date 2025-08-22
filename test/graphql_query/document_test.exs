defmodule GraphqlQuery.DocumentTest do
  use ExUnit.Case
  alias GraphqlQuery.Document

  doctest GraphqlQuery.Document

  describe "Document.new/2" do
    test "creates document with default options" do
      query = "query { user { id } }"
      document = Document.new(query)

      assert %Document{
               query: ^query,
               type: :query,
               variables: %{},
               fragments: [],
               schema: nil,
               path: nil
             } = document

      assert is_binary(document.name)
    end

    test "creates document with custom options" do
      query = "query { user { id } }"

      document =
        Document.new(query,
          type: :schema,
          schema: MySchema,
          path: "/path/to/query.gql",
          fragments: []
        )

      assert %Document{
               query: ^query,
               type: :schema,
               variables: %{},
               fragments: [],
               schema: MySchema,
               path: "/path/to/query.gql"
             } = document
    end

    test "creates fragment when type is :fragment" do
      fragment_query = "fragment UserFields on User { id name }"

      result = Document.new(fragment_query, type: :fragment)

      assert %GraphqlQuery.Fragment{} = result
    end

    test "generates consistent signature for same query" do
      query = "query { user { id } }"
      doc1 = Document.new(query)
      doc2 = Document.new(query)

      assert doc1.name == doc2.name
    end

    test "generates different signature for different queries" do
      query1 = "query { user { id } }"
      query2 = "query { user { name } }"
      doc1 = Document.new(query1)
      doc2 = Document.new(query2)

      assert doc1.name != doc2.name
    end
  end

  describe "Document.set_schema/2" do
    test "sets schema on document" do
      query = "query { user { id } }"
      document = Document.new(query)

      updated_document = Document.set_schema(document, MySchema)

      assert updated_document.schema == MySchema
    end
  end

  describe "Document variable management" do
    setup do
      query = "query GetUser($id: ID!) { user(id: $id) { id name } }"
      document = Document.new(query)
      {:ok, document: document}
    end

    test "add_variable/3 adds a single variable", %{document: document} do
      updated_document = Document.add_variable(document, :user_id, "123")

      assert updated_document.variables == %{user_id: "123"}
    end

    test "add_variables/2 with map adds multiple variables", %{document: document} do
      variables = %{user_id: "123", active: true}
      updated_document = Document.add_variables(document, variables)

      assert updated_document.variables == variables
    end

    test "add_variables/2 with keyword list adds multiple variables", %{document: document} do
      variables = [user_id: "123", active: true]
      updated_document = Document.add_variables(document, variables)

      assert updated_document.variables == %{user_id: "123", active: true}
    end

    test "add_variables/2 with nested keyword list converts properly", %{document: document} do
      variables = [user: [id: "123", profile: [name: "John"]]]
      updated_document = Document.add_variables(document, variables)

      expected = %{user: %{id: "123", profile: %{name: "John"}}}
      assert updated_document.variables == expected
    end

    test "multiple variable operations accumulate", %{document: document} do
      updated_document =
        document
        |> Document.add_variable(:user_id, "123")
        |> Document.add_variables(%{active: true, count: 5})

      expected = %{user_id: "123", active: true, count: 5}
      assert updated_document.variables == expected
    end
  end

  describe "Document fragment management" do
    setup do
      query = "query { user { ...UserFields } }"
      document = Document.new(query)

      fragment = Document.new("fragment UserFields on User { id name }", type: :fragment)

      {:ok, document: document, fragment: fragment}
    end

    test "add_fragment/2 adds a single fragment", %{document: document, fragment: fragment} do
      updated_document = Document.add_fragment(document, fragment)

      assert updated_document.fragments == [fragment]
    end

    test "add_fragments/2 adds multiple fragments", %{document: document} do
      fragment1 = Document.new("fragment UserFields on User { id name }", type: :fragment)
      fragment2 = Document.new("fragment PostFields on Post { title content }", type: :fragment)

      updated_document = Document.add_fragments(document, [fragment1, fragment2])

      assert length(updated_document.fragments) == 2
      assert fragment1 in updated_document.fragments
      assert fragment2 in updated_document.fragments
    end

    test "duplicate fragments are deduplicated by name", %{document: document, fragment: fragment} do
      # Since Document.new generates hash-based names, fragments with different content
      # will have different names and won't be deduplicated. Let's test with same content
      duplicate_fragment =
        Document.new("fragment UserFields on User { id name }", type: :fragment)

      updated_document =
        document
        |> Document.add_fragment(fragment)
        |> Document.add_fragment(duplicate_fragment)

      # Fragments with identical content should have same hash-based name and be deduplicated
      assert length(updated_document.fragments) == 1
    end

    test "fragments without names are not deduplicated", %{document: document} do
      fragment1 = Document.new("fragment on User { id }", type: :fragment)
      fragment2 = Document.new("fragment on User { name }", type: :fragment)

      updated_document = Document.add_fragments(document, [fragment1, fragment2])

      assert length(updated_document.fragments) == 2
    end

    test "only_fragments/1 filters out non-fragment items and uniq by name" do
      query = Document.new("query { user { id } }")
      fragment = Document.new("fragment UserFields on User { id name }", type: :fragment)

      mixed_list = [fragment, "not a fragment", %{not: "fragment"}, fragment]
      query = Document.add_fragments(query, mixed_list)

      assert query.fragments == [fragment]
    end
  end

  describe "Document.format_query_with_fragments/1" do
    test "formats query with no fragments" do
      query = "query { user { id } }"
      document = Document.new(query)

      result = Document.format_query_with_fragments(document)

      assert result == "query { user { id } }"
    end

    test "formats query with fragments" do
      query = "query { user { ...UserFields } }"
      document = Document.new(query)

      fragment = Document.new("fragment UserFields on User { id name }", type: :fragment)

      updated_document = Document.add_fragment(document, fragment)
      result = Document.format_query_with_fragments(updated_document)

      assert result =~ "query { user { ...UserFields } }"
      assert result =~ "fragment UserFields on User { id name }"
    end

    test "handles multiple fragments" do
      query = "query { user { ...UserFields } posts { ...PostFields } }"
      document = Document.new(query)

      fragment1 = Document.new("fragment UserFields on User { id name }", type: :fragment)
      fragment2 = Document.new("fragment PostFields on Post { title content }", type: :fragment)

      updated_document = Document.add_fragments(document, [fragment1, fragment2])
      result = Document.format_query_with_fragments(updated_document)

      assert result =~ "query { user { ...UserFields } posts { ...PostFields } }"
      assert result =~ "fragment UserFields on User { id name }"
      assert result =~ "fragment PostFields on Post { title content }"
    end
  end

  describe "String.Chars protocol" do
    test "converts document to string using format_query_with_fragments" do
      query = "query { user { ...UserFields } }"
      document = Document.new(query)

      fragment = Document.new("fragment UserFields on User { id name }", type: :fragment)

      updated_document = Document.add_fragment(document, fragment)
      result = to_string(updated_document)

      assert result =~ "query { user { ...UserFields } }"
      assert result =~ "fragment UserFields on User { id name }"
    end
  end

  describe "Inspect protocol" do
    test "provides readable inspection of document" do
      query = "query GetUser { user { id } }"
      document = Document.new(query, schema: MySchema)

      inspected = inspect(document)

      assert inspected ==
               "%GraphqlQuery.Document{name: \"44106063\", query: \"query GetUser { user { id } }\", variables: %{}, fragments: [], schema: MySchema, path: nil, type: :query, document_info: nil}"
    end

    test "handles nil name in inspection" do
      document = %Document{
        name: nil,
        query: "query { user { id } }",
        variables: %{},
        fragments: [],
        schema: nil,
        path: nil,
        type: :query
      }

      inspected = inspect(document)

      assert inspected =~ "name: nil"
    end
  end

  if Code.ensure_loaded?(Jason) do
    describe "Jason.Encoder protocol" do
      test "encodes document to JSON with query and variables" do
        query = "query GetUser($id: ID!) { user(id: $id) { id name } }"

        document =
          Document.new(query)
          |> Document.add_variables(%{id: "123", active: true})

        json = Jason.encode!(document)
        parsed = Jason.decode!(json)

        expected_query = Document.format_query_with_fragments(document)
        assert parsed["query"] == expected_query
        assert parsed["variables"] == %{"id" => "123", "active" => true}
      end

      test "encodes document with fragments correctly" do
        query = "query { user { ...UserFields } }"
        document = Document.new(query)

        fragment = Document.new("fragment UserFields on User { id name }", type: :fragment)

        updated_document =
          document
          |> Document.add_fragment(fragment)
          |> Document.add_variable(:user_id, "456")

        json = Jason.encode!(updated_document)
        parsed = Jason.decode!(json)

        assert parsed["query"] =~ "query { user { ...UserFields } }"
        assert parsed["query"] =~ "fragment UserFields on User { id name }"
        assert parsed["variables"] == %{"user_id" => "456"}
      end

      test "handles empty variables" do
        query = "query { user { id } }"
        document = Document.new(query)

        json = Jason.encode!(document)
        parsed = Jason.decode!(json)

        assert parsed["query"] == "query { user { id } }"
        assert parsed["variables"] == %{}
      end
    end
  end

  if Code.ensure_loaded?(JSON) do
    describe "JSON.Encoder protocol" do
      test "encodes document to JSON with query and variables" do
        query = "query GetUser($id: ID!) { user(id: $id) { id name } }"

        document =
          Document.new(query)
          |> Document.add_variables(%{id: "123", active: true})

        json = JSON.encode!(document)
        parsed = JSON.decode!(json)

        expected_query = Document.format_query_with_fragments(document)
        assert parsed["query"] == expected_query
        assert parsed["variables"] == %{"id" => "123", "active" => true}
      end

      test "encodes document with fragments correctly" do
        query = "query { user { ...UserFields } }"
        document = Document.new(query)

        fragment = Document.new("fragment UserFields on User { id name }", type: :fragment)

        updated_document =
          document
          |> Document.add_fragment(fragment)
          |> Document.add_variable(:user_id, "456")

        json = JSON.encode!(updated_document)
        parsed = JSON.decode!(json)

        assert parsed["query"] =~ "query { user { ...UserFields } }"
        assert parsed["query"] =~ "fragment UserFields on User { id name }"
        assert parsed["variables"] == %{"user_id" => "456"}
      end

      test "handles empty variables" do
        query = "query { user { id } }"
        document = Document.new(query)

        json = JSON.encode!(document)
        parsed = JSON.decode!(json)

        assert parsed["query"] == "query { user { id } }"
        assert parsed["variables"] == %{}
      end
    end
  end
end
