if Code.ensure_loaded?(Absinthe) do
  defmodule GraphqlQuery.Schema.Absinthe do
    def schema_from_absinthe!(schema) do
      case schema_from_absinthe(schema) do
        {:ok, string} ->
          string

        {:error, reason} ->
          raise "Failed to load schema from Absinthe schema #{inspect(schema)}: #{reason}"
      end
    end

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

      with {:ok, blueprint, _phases} <-
             Absinthe.Pipeline.run(
               schema.__absinthe_blueprint__(),
               pipeline
             ) do
        {:ok, inspect(blueprint, pretty: true)}
      else
        _ -> {:error, "Failed to render schema"}
      end
    end
  end
end
