defmodule GraphqlQuery.FragmentTest do
  use ExUnit.Case
  alias GraphqlQuery.{Fragment, Document}

  describe "Fragment struct" do
    test "has correct struct fields" do
      fragment = %Fragment{
        name: "UserFields",
        fragment: "fragment UserFields on User { id name }",
        path: "/path/to/fragment.gql",
        schema: MySchema
      }

      assert fragment.name == "UserFields"
      assert fragment.fragment == "fragment UserFields on User { id name }"
      assert fragment.path == "/path/to/fragment.gql"
      assert fragment.schema == MySchema
    end

    test "allows nil values for optional fields" do
      fragment = %Fragment{
        name: "UserFields",
        fragment: "fragment UserFields on User { id name }",
        path: nil,
        schema: nil
      }

      assert fragment.name == "UserFields"
      assert fragment.fragment == "fragment UserFields on User { id name }"
      assert fragment.path == nil
      assert fragment.schema == nil
    end
  end

  describe "Fragment.from_query/1" do
    test "creates fragment from Document" do
      query = "fragment UserFields on User { id name email }"
      document = Document.new(query, path: "/test/fragment.gql", schema: TestSchema)

      fragment = Fragment.from_query(document)

      assert %Fragment{
               name: _name,
               fragment: ^query,
               path: "/test/fragment.gql",
               schema: TestSchema
             } = fragment

      assert is_binary(fragment.name)
    end

    test "converts Document to string for fragment content" do
      query = "fragment PostFields on Post { title content }"
      document = Document.new(query)

      fragment = Fragment.from_query(document)

      assert fragment.fragment == query
    end

    test "preserves Document metadata in Fragment" do
      query = "fragment UserProfile on User { id name avatar }"
      document = Document.new(query, 
        path: "/graphql/fragments/user.gql",
        schema: UserSchema
      )

      fragment = Fragment.from_query(document)

      assert fragment.name == document.name
      assert fragment.path == "/graphql/fragments/user.gql"
      assert fragment.schema == UserSchema
    end

    test "handles Document with nil metadata" do
      query = "fragment SimpleFragment on Type { field }"
      document = Document.new(query)

      fragment = Fragment.from_query(document)

      assert fragment.path == nil
      assert fragment.schema == nil
      assert fragment.name == document.name
      assert fragment.fragment == query
    end
  end

  describe "String.Chars protocol" do
    test "converts fragment to trimmed string" do
      fragment = %Fragment{
        name: "UserFields",
        fragment: "  fragment UserFields on User { id name }  ",
        path: nil,
        schema: nil
      }

      result = to_string(fragment)

      assert result == "fragment UserFields on User { id name }"
    end

    test "handles fragment without extra whitespace" do
      fragment_content = "fragment PostFields on Post { title content }"
      fragment = %Fragment{
        name: "PostFields",
        fragment: fragment_content,
        path: nil,
        schema: nil
      }

      result = to_string(fragment)

      assert result == fragment_content
    end

    test "trims multiline fragment content" do
      fragment_content = """
      
      fragment UserDetails on User {
        id
        name
        email
        profile {
          bio
          avatar
        }
      }
      
      """

      fragment = %Fragment{
        name: "UserDetails",
        fragment: fragment_content,
        path: nil,
        schema: nil
      }

      result = to_string(fragment)

      expected = """
      fragment UserDetails on User {
        id
        name
        email
        profile {
          bio
          avatar
        }
      }
      """

      assert result == String.trim(expected)
    end

    test "handles empty fragment content" do
      fragment = %Fragment{
        name: "EmptyFragment",
        fragment: "   ",
        path: nil,
        schema: nil
      }

      result = to_string(fragment)

      assert result == ""
    end
  end

  describe "Integration with Document.new/2" do
    test "Document.new with type: :fragment creates Fragment" do
      fragment_query = "fragment UserFields on User { id name email }"

      result = Document.new(fragment_query, type: :fragment)

      assert %Fragment{} = result
      assert result.fragment == fragment_query
      assert is_binary(result.name)
    end

    test "Document.new with type: :fragment preserves options" do
      fragment_query = "fragment UserProfile on User { id name avatar }"
      
      result = Document.new(fragment_query, 
        type: :fragment,
        path: "/fragments/user.gql",
        schema: MySchema
      )

      assert %Fragment{
               fragment: ^fragment_query,
               path: "/fragments/user.gql",
               schema: MySchema
             } = result
    end

    test "Fragment from Document.new can be used with Document.add_fragment" do
      query = "query { user { ...UserFields } }"
      document = Document.new(query)

      fragment = Document.new("fragment UserFields on User { id name }", type: :fragment)

      updated_document = Document.add_fragment(document, fragment)

      assert length(updated_document.fragments) == 1
      assert fragment in updated_document.fragments
    end

    test "Multiple fragments created via Document.new work together" do
      query = "query { user { ...UserFields } posts { ...PostFields } }"
      document = Document.new(query)

      user_fragment = Document.new("fragment UserFields on User { id name }", type: :fragment)
      post_fragment = Document.new("fragment PostFields on Post { title content }", type: :fragment)

      updated_document = Document.add_fragments(document, [user_fragment, post_fragment])

      assert length(updated_document.fragments) == 2
      assert user_fragment in updated_document.fragments
      assert post_fragment in updated_document.fragments

      result_string = to_string(updated_document)
      assert result_string =~ "query { user { ...UserFields } posts { ...PostFields } }"
      assert result_string =~ "fragment UserFields on User { id name }"
      assert result_string =~ "fragment PostFields on Post { title content }"
    end
  end

  describe "Fragment comparison and equality" do
    test "fragments with same content are considered equal" do
      fragment1 = Document.new("fragment UserFields on User { id name }", type: :fragment)
      fragment2 = Document.new("fragment UserFields on User { id name }", type: :fragment)

      # Same content should generate same hash-based name
      assert fragment1.name == fragment2.name
      assert fragment1.fragment == fragment2.fragment
    end

    test "fragments with different content have different names" do
      fragment1 = Document.new("fragment UserFields on User { id name }", type: :fragment)
      fragment2 = Document.new("fragment UserFields on User { id email }", type: :fragment)

      # Different content should generate different hash-based names
      assert fragment1.name != fragment2.name
      assert fragment1.fragment != fragment2.fragment
    end
  end

  describe "Edge cases and error handling" do
    test "Fragment.from_query handles Document with fragments" do
      # Create a Document that already has fragments
      main_query = "query { user { ...UserFields } }"
      document = Document.new(main_query)
      
      existing_fragment = Document.new("fragment UserFields on User { id }", type: :fragment)
      document_with_fragments = Document.add_fragment(document, existing_fragment)

      # Converting document with fragments to Fragment should still work
      result_fragment = Fragment.from_query(document_with_fragments)

      assert %Fragment{} = result_fragment
      assert result_fragment.fragment =~ "query { user { ...UserFields } }"
      # The result should include the fragment definition when converted to string
      assert to_string(result_fragment) =~ "fragment UserFields on User { id }"
    end

    test "handles very long fragment names and content" do
      long_fragment_name = String.duplicate("VeryLong", 50)
      long_fields = String.duplicate("id name email ", 100)
      long_fragment = "fragment #{long_fragment_name} on User { #{long_fields} }"
      
      result = Document.new(long_fragment, type: :fragment)

      assert %Fragment{} = result
      assert is_binary(result.name)
      assert String.length(result.fragment) > 1000
    end
  end
end