defmodule GraphqlQuery.Formatter do
  @moduledoc """
  Mix formatter plugin for GraphQL files and sigils.

  Integrates with `mix format` to automatically format GraphQL queries in
  .graphql/.gql files and ~GQL sigils. Skips formatting when queries contain
  dynamic interpolation to avoid unexpected results.
  """
  @behaviour Mix.Tasks.Format

  @impl true
  def features(_opts) do
    [sigils: [:GQL], extensions: [".graphql", ".gql"]]
  end

  @impl true
  def format(contents, _opts) do
    if GraphqlQuery.Parser.has_dynamic_parts?(contents) do
      # We don't try to format with dynamic parts, it can end with unexpected results
      contents
    else
      GraphqlQuery.Format.format(contents)
    end
  end
end
