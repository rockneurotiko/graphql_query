defmodule Test.FederationSchema do
  @moduledoc false
  use GraphqlQuery.Schema, federation: true

  @impl GraphqlQuery.Schema
  def schema do
    ~GQL"""
    extend schema @link(url: "https://specs.apollo.dev/federation/v2.0", import: ["@key", "@shareable", "@external", "@requires"])

    type Query {
      user(id: ID!): User
      product(id: ID!): Product
    }

    type User @key(fields: "id") {
      id: ID!
      name: String! @shareable
      email: String!
    }

    type Product @key(fields: "id") {
      id: ID!
      title: String! @shareable
    }
    """sF
  end

  @impl GraphqlQuery.Schema
  def schema_path, do: nil
end
