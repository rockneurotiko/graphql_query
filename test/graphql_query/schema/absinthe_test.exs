defmodule GraphqlQuery.Schema.AbsintheTest do
  use ExUnit.Case, async: true

  alias GraphqlQuery.Schema.Absinthe, as: SchemaAbsinthe

  if Code.ensure_loaded?(Absinthe) do
    describe "schema_from_absinthe/1" do
      defmodule TestSchema do
        use Absinthe.Schema

        query do
          field :hello, :string do
            resolve(fn _, _, _ -> {:ok, "world"} end)
          end
        end
      end

      test "returns ok tuple with schema blueprint string for valid schema" do
        assert {:ok, schema} = SchemaAbsinthe.schema_from_absinthe(TestSchema)

        assert schema ==
                 "schema {\n  query: RootQueryType\n}\n\ntype RootQueryType {\n  hello: String\n}\n"
      end

      test "returns error tuple for invalid schema" do
        defmodule InvalidSchema do
          # Not a proper Absinthe schema
        end

        assert {:error, _reason} = SchemaAbsinthe.schema_from_absinthe(InvalidSchema)
      end
    end

    describe "schema_from_absinthe!/1" do
      defmodule TestSchema2 do
        use Absinthe.Schema

        query do
          field :test, :string do
            resolve(fn _, _, _ -> {:ok, "test"} end)
          end
        end
      end

      test "returns schema blueprint string for valid schema" do
        schema = SchemaAbsinthe.schema_from_absinthe!(TestSchema2)

        assert schema ==
                 "schema {\n  query: RootQueryType\n}\n\ntype RootQueryType {\n  test: String\n}\n"
      end

      test "raises exception for invalid schema" do
        defmodule InvalidSchema2 do
          # Not a proper Absinthe schema
        end

        assert_raise RuntimeError, ~r/Failed to load schema from Absinthe schema/, fn ->
          SchemaAbsinthe.schema_from_absinthe!(InvalidSchema2)
        end
      end
    end
  else
    # If Absinthe is not loaded, create placeholder tests
    test "Absinthe not available" do
      assert true
    end
  end
end
