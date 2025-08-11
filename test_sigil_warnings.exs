defmodule TestSigilWarnings do
  import GraphqlQuery

  # This should generate a warning
  def invalid_query do
    ~G"""
    query TestInvalid($unused: String) {
      user {
        id
        name
      }
    }
    """
  end

  # This should not generate a warning
  def valid_query do
    ~G"""
    query TestValid($id: ID!) {
      user(id: $id) {
        id
        name
        email
      }
    }
    """
  end
end