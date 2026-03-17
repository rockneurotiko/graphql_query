defmodule Test.ErrorSchema do
  @moduledoc false
  use GraphqlQuery.Schema

  @impl GraphqlQuery.Schema
  def schema do
    ~GQL"""
    type Query {
      user(id: ID): User
    }

    type User {
      id: ID!
      name: String!
      email: String!
      oldEmail: String! @deprecated(reason: "Use 'email' field instead")
    }

    directive @deprecated(reason: String!) on FIELD_DEFINITION | ENUM_VALUE

    directive @deprecated(reason: String!) on FIELD_DEFINITION | ENUM_VALUE
    """si
  end

  @impl GraphqlQuery.Schema
  def schema_path, do: nil
end
