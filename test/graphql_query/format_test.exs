defmodule GraphqlQuery.FormatTest do
  use ExUnit.Case

  alias GraphqlQuery.Format

  describe "format/1" do
    test "formats GraphQL queries" do
      non_formatted = """
      query GetUser($id: ID!) { user(id: $id) {
          id
          name
          email
          posts { title content
          } } }
      """

      formatted_query = """
      query GetUser($id: ID!) {
        user(id: $id) {
          id
          name
          email
          posts {
            title
            content
          }
        }
      }
      """

      assert formatted_query == Format.format(non_formatted)

      # Test with invalid query - should return original
      invalid_query = "query T{"
      assert Format.format(invalid_query) == invalid_query
    end

    test "formats GraphQL schemas" do
      non_formatted_schema = """
      type Query { user(id: ID!): User users: [User!]! }

      type User{id:ID! name:String! email:String!
      posts:[Post!]! }

      type Post{id:ID!
      title:String!content:String!
      author:User!}
      """

      formatted_schema = """
      type Query {
        user(id: ID!): User
        users: [User!]!
      }

      type User {
        id: ID!
        name: String!
        email: String!
        posts: [Post!]!
      }

      type Post {
        id: ID!
        title: String!
        content: String!
        author: User!
      }
      """

      assert formatted_schema == Format.format(non_formatted_schema)
    end

    test "formats schema with interfaces" do
      non_formatted_interface = """
      interface Node{id:ID!}type User implements Node{id:ID! name:String!}
      type Post implements Node{id:ID! title:String!}
      """

      formatted_interface = """
      interface Node {
        id: ID!
      }

      type User implements Node {
        id: ID!
        name: String!
      }

      type Post implements Node {
        id: ID!
        title: String!
      }
      """

      assert formatted_interface == Format.format(non_formatted_interface)
    end

    test "formats schema with unions and enums" do
      non_formatted_union = """
      union SearchResult=User|Post enum UserRole{ADMIN USER MODERATOR}
      type User{id:ID! role:UserRole!}
      """

      formatted_union = """
      union SearchResult = User | Post

      enum UserRole {
        ADMIN
        USER
        MODERATOR
      }

      type User {
        id: ID!
        role: UserRole!
      }
      """

      assert formatted_union == Format.format(non_formatted_union)
    end

    test "formats schema with input types" do
      non_formatted_input = """
      input CreateUserInput{name:String! email:String! age:Int}
      input UpdateUserInput{name:String email:String age:Int}
      type Mutation{createUser(input:CreateUserInput!):User!}
      """

      formatted_input = """
      input CreateUserInput {
        name: String!
        email: String!
        age: Int
      }

      input UpdateUserInput {
        name: String
        email: String
        age: Int
      }

      type Mutation {
        createUser(input: CreateUserInput!): User!
      }
      """

      assert formatted_input == Format.format(non_formatted_input)
    end

    test "formats schema with directives" do
      non_formatted_directive = """
      directive @auth(role:String!)on FIELD_DEFINITION
      type User{id:ID! email:String!@auth(role:"user")}
      """

      formatted_directive = """
      directive @auth(role: String!) on FIELD_DEFINITION

      type User {
        id: ID!
        email: String! @auth(role: "user")
      }
      """

      assert formatted_directive == Format.format(non_formatted_directive)
    end

    test "formats schema with custom scalars" do
      non_formatted_scalar = """
      scalar DateTime scalar JSON
      type User{id:ID! createdAt:DateTime! metadata:JSON}
      """

      formatted_scalar = """
      scalar DateTime

      scalar JSON

      type User {
        id: ID!
        createdAt: DateTime!
        metadata: JSON
      }
      """

      assert formatted_scalar == Format.format(non_formatted_scalar)
    end

    test "handles complex schema formatting" do
      complex_schema = """
      schema{query:Query mutation:Mutation subscription:Subscription}
      type Query{user(id:ID!):User posts(limit:Int=10):[Post!]!}
      type Mutation{createUser(input:CreateUserInput!):User! updateUser(id:ID! input:UpdateUserInput!):User!}
      type Subscription{userUpdated(id:ID!):User!}
      """

      formatted_complex = """
      schema {
        query: Query
        mutation: Mutation
        subscription: Subscription
      }

      type Query {
        user(id: ID!): User
        posts(limit: Int = 10): [Post!]!
      }

      type Mutation {
        createUser(input: CreateUserInput!): User!
        updateUser(id: ID!, input: UpdateUserInput!): User!
      }

      type Subscription {
        userUpdated(id: ID!): User!
      }
      """

      assert formatted_complex == Format.format(complex_schema)
    end

    test "preserves original content for invalid schemas" do
      invalid_schema = """
      type Query {
        user: UnknownType
        # Missing closing brace
      """

      # Should return original content when parsing fails
      assert Format.format(invalid_schema) == invalid_schema
    end
  end
end
