defmodule Test.Schema do
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
      oldName: String! @deprecated
      email: String!
      oldEmail: String! @deprecated(reason: "Use 'email' field instead")
    }
    """s
  end

  @impl GraphqlQuery.Schema
  def schema_path, do: nil
end
