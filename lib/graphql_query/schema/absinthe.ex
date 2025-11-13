if Code.ensure_loaded?(Absinthe) do
  defmodule GraphqlQuery.Schema.Absinthe do
    @moduledoc """
    Utilities for extracting schema information from Absinthe schemas.

    This module provides functions to convert Absinthe schema definitions
    into inspectable string representations for analysis and validation.
    """

    @doc """
    Extracts schema information from an Absinthe schema and returns it as a string.

    Raises an exception if the schema extraction fails.

    ## Parameters

    - `schema` - An Absinthe schema module

    ## Returns

    A string representation of the schema blueprint.

    ## Raises

    Raises a runtime error if schema extraction fails.

    ## Examples

        iex> GraphqlQuery.Schema.Absinthe.schema_from_absinthe!(MyApp.Schema)
        "type Query { ... }"
    """
    @spec schema_from_absinthe!(module()) :: String.t()
    def schema_from_absinthe!(schema) do
      case schema_from_absinthe(schema) do
        {:ok, string} ->
          string

        {:error, reason} ->
          raise "Failed to load schema from Absinthe schema #{inspect(schema)}: #{reason}"
      end
    end

    @doc """
    Extracts schema information from an Absinthe schema.

    This function processes an Absinthe schema through the schema pipeline
    to generate a blueprint representation.

    ## Parameters

    - `schema` - An Absinthe schema module

    ## Returns

    - `{:ok, string}` - Success with the schema blueprint as a string
    - `{:error, reason}` - Error with failure reason

    ## Examples

        iex> GraphqlQuery.Schema.Absinthe.schema_from_absinthe(MyApp.Schema)
        {:ok, "type Query { ... }"}

        iex> GraphqlQuery.Schema.Absinthe.schema_from_absinthe(InvalidSchema)
        {:error, "Failed to render schema"}

    """
    @spec schema_from_absinthe(module()) :: {:ok, String.t()} | {:error, String.t()}
    def schema_from_absinthe(schema) do
      Code.ensure_compiled!(schema)

      # Start Absinthe.Schema if using persistent term provider
      if schema.__absinthe_schema_provider__() == Absinthe.Schema.PersistentTerm do
        Supervisor.start_link([{Absinthe.Schema, schema}], strategy: :one_for_one)
      end

      pipeline =
        schema
        |> Absinthe.Pipeline.for_schema(prototype_schema: schema.__absinthe_prototype_schema__())
        |> Absinthe.Pipeline.upto({Absinthe.Phase.Schema.Validation.Result, pass: :final})
        |> Absinthe.Schema.apply_modifiers(schema)

      case Absinthe.Pipeline.run(schema.__absinthe_blueprint__(), pipeline) do
        {:ok, blueprint, _phases} ->
          {:ok, inspect(blueprint, pretty: true)}

        {:error, error, _phases} when is_binary(error) ->
          {:error, error}

        {:error, error, _phases} ->
          {:error, inspect(error)}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
end
