defmodule GraphqlQuery.Formatter do
  @behaviour Mix.Tasks.Format

  def features(_opts) do
    [sigils: [:GQL], extensions: [".graphql", ".gql"]]
  end

  def format(contents, _opts) do
    GraphqlQuery.format(contents)
  end
end
