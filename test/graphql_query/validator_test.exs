defmodule GraphqlQuery.ValidatorTest do
  use ExUnit.Case

  alias GraphqlQuery.Validator

  describe "validate/1" do
    test "uses default document name on errors" do
      # Test that the default document name is used in error messages
      assert {:error, [error]} = Validator.validate("query T() { field }")
      assert error.message =~ "expected a Variable Definition"
      assert error.message =~ "document.graphql:1:9"
    end

    test "uses specified document name on errors" do
      # Test that the default document name is used in error messages
      assert {:error, [error]} = Validator.validate("query T() { field }", "test.graphql")
      assert error.message =~ "expected a Variable Definition"
      assert error.message =~ "test.graphql:1:9"
    end

    test "validates correct GraphQL queries" do
      assert Validator.validate("query TestQuery($a: String!) { user(id: $a) { id name } }") ==
               :ok
    end

    test "validates GraphQL queries with syntax errors" do
      result = Validator.validate("query T { field\n? }")
      assert {:error, [error]} = result
      assert error.message =~ "Error: syntax error: Unexpected character \"?\""
    end

    test "validates GraphQL queries with unused variables" do
      # Query with unused variable should return validation error
      result = Validator.validate("query T($a: String) { field }")
      assert {:error, [error]} = result
      assert error.message =~ "unused variable: `$a`"
    end
  end
end
