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
      email: String!
    }
    """s
  end

  @impl GraphqlQuery.Schema
  def schema_path, do: nil
end
