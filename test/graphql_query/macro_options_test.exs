defmodule GraphqlQuery.MacroOptionsTest do
  use ExUnit.Case
  alias GraphqlQuery.MacroOptions

  doctest GraphqlQuery.MacroOptions

  describe "validate/1" do
    test "validates valid options" do
      opts = [
        ignore: true,
        type: :query,
        schema: MySchema,
        evaluate: false,
        runtime: true,
        fragments: []
      ]

      assert {:ok, validated} = MacroOptions.validate(opts)
      assert %MacroOptions{} = validated
      assert validated.ignore == true
      assert validated.type == :query
      assert validated.schema == MySchema
      assert validated.evaluate == false
      assert validated.runtime == true
      assert validated.fragments == []
    end

    test "validates with defaults for missing options" do
      opts = []

      assert {:ok, validated} = MacroOptions.validate(opts)
      assert %MacroOptions{} = validated
      assert validated.ignore == nil
      assert validated.type == :query
      assert validated.schema == :not_set
      assert validated.evaluate == nil
      assert validated.runtime == nil
      assert validated.fragments == []
    end

    test "validates partial options" do
      opts = [type: :fragment, ignore: false]

      assert {:ok, validated} = MacroOptions.validate(opts)
      assert %MacroOptions{} = validated
      assert validated.ignore == false
      assert validated.type == :fragment
      assert validated.schema == :not_set
      assert validated.evaluate == nil
      assert validated.runtime == nil
      assert validated.fragments == []
    end

    test "validates schema type options" do
      opts = [type: :schema, schema: nil]

      assert {:ok, validated} = MacroOptions.validate(opts)
      assert validated.type == :schema
      assert validated.schema == nil
    end

    test "validates with fragment list" do
      fragments = [
        %GraphqlQuery.Fragment{
          name: "UserFragment",
          fragment: "fragment UserFragment on User { id }"
        },
        %GraphqlQuery.Fragment{
          name: "PostFragment",
          fragment: "fragment PostFragment on Post { title }"
        }
      ]

      opts = [fragments: fragments]

      assert {:ok, validated} = MacroOptions.validate(opts)
      assert validated.fragments == fragments
    end

    test "accepts any atom for type" do
      opts = [type: :invalid]

      assert {:ok, validated} = MacroOptions.validate(opts)
      assert validated.type == :invalid
    end

    test "returns error for invalid ignore value" do
      opts = [ignore: "invalid"]

      assert {:error, %NimbleOptions.ValidationError{} = error} = MacroOptions.validate(opts)
      assert error.message =~ "expected :ignore option to match"
      assert error.key == :ignore
    end

    test "returns error for invalid evaluate value" do
      opts = [evaluate: "invalid"]

      assert {:error, %NimbleOptions.ValidationError{} = error} = MacroOptions.validate(opts)
      assert error.message =~ "expected :evaluate option to match"
      assert error.key == :evaluate
    end

    test "returns error for invalid runtime value" do
      opts = [runtime: "invalid"]

      assert {:error, %NimbleOptions.ValidationError{} = error} = MacroOptions.validate(opts)
      assert error.message =~ "expected :runtime option to match"
      assert error.key == :runtime
    end

    test "returns error for invalid fragments value" do
      opts = [fragments: "invalid"]

      assert {:error, %NimbleOptions.ValidationError{} = error} = MacroOptions.validate(opts)
      assert error.message =~ "expected list"
      assert error.key == :fragments
    end

    test "validates nil values for boolean options" do
      opts = [ignore: nil, evaluate: nil, runtime: nil]

      assert {:ok, validated} = MacroOptions.validate(opts)
      assert validated.ignore == nil
      assert validated.evaluate == nil
      assert validated.runtime == nil
    end

    test "validates all valid type values" do
      for type <- [:query, :schema, :fragment] do
        opts = [type: type]
        assert {:ok, validated} = MacroOptions.validate(opts)
        assert validated.type == type
      end
    end
  end

  describe "validate!/1" do
    test "returns validated options on success" do
      opts = [type: :fragment, ignore: true]

      validated = MacroOptions.validate!(opts)
      assert %MacroOptions{} = validated
      assert validated.type == :fragment
      assert validated.ignore == true
    end

    test "raises ArgumentError on validation failure" do
      opts = [ignore: "invalid"]

      assert_raise ArgumentError, ~r/Invalid options:/, fn ->
        MacroOptions.validate!(opts)
      end
    end

    test "raises ArgumentError with detailed error message" do
      opts = [ignore: "not_boolean"]

      assert_raise ArgumentError, fn ->
        MacroOptions.validate!(opts)
      end
    end

    test "works with empty options" do
      validated = MacroOptions.validate!([])
      assert %MacroOptions{} = validated
      assert validated.type == :query
      assert validated.ignore == nil
    end
  end

  describe "docs/0" do
    test "returns documentation string" do
      docs = MacroOptions.docs()
      assert is_binary(docs)
      assert String.length(docs) > 0
    end

    test "documentation contains option descriptions" do
      docs = MacroOptions.docs()

      # Check that all options are documented
      assert docs =~ ":ignore"
      assert docs =~ ":type"
      assert docs =~ ":schema"
      assert docs =~ ":evaluate"
      assert docs =~ ":runtime"
      assert docs =~ ":fragments"
    end

    test "documentation contains type information" do
      docs = MacroOptions.docs()

      # Check that types are documented
      assert docs =~ "atom"
      assert docs =~ ":query"
      assert docs =~ "list"
    end

    test "documentation contains default values" do
      docs = MacroOptions.docs()

      # Check that defaults are mentioned
      assert docs =~ "default"
    end
  end

  describe "struct creation" do
    test "creates struct with default fields" do
      macro_options = struct(MacroOptions)

      assert macro_options.ignore == nil
      assert macro_options.type == nil
      assert macro_options.schema == nil
      assert macro_options.evaluate == nil
      assert macro_options.runtime == nil
      assert macro_options.fragments == nil
    end

    test "creates struct with custom values" do
      macro_options = %MacroOptions{
        ignore: true,
        type: :fragment,
        schema: MySchema,
        evaluate: true,
        runtime: false,
        fragments: [
          %GraphqlQuery.Fragment{name: "test", fragment: "fragment test on User { id }"}
        ]
      }

      assert macro_options.ignore == true
      assert macro_options.type == :fragment
      assert macro_options.schema == MySchema
      assert macro_options.evaluate == true
      assert macro_options.runtime == false
      assert length(macro_options.fragments) == 1
    end
  end

  describe "integration with NimbleOptions" do
    test "validates complex combinations" do
      opts = [
        type: :query,
        schema: MyApp.Schema,
        ignore: false,
        runtime: true,
        evaluate: false,
        fragments: []
      ]

      assert {:ok, validated} = MacroOptions.validate(opts)
      assert validated.type == :query
      assert validated.schema == MyApp.Schema
      assert validated.ignore == false
      assert validated.runtime == true
      assert validated.evaluate == false
      assert validated.fragments == []
    end

    test "handles unknown options" do
      opts = [unknown_option: true, type: :query]

      assert {:error, %NimbleOptions.ValidationError{} = error} = MacroOptions.validate(opts)
      assert error.message =~ "unknown options"
      assert error.message =~ "unknown_option"
    end
  end
end
