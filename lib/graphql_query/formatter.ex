defmodule GraphqlQuery.Formatter do
  @behaviour Mix.Tasks.Format

  def features(_opts) do
    [sigils: [:GQL], extensions: [".graphql", ".gql"]]
  end

  def format(contents, _opts) do
    if GraphqlQuery.Parser.has_dynamic_parts?(contents) do
      # We don't try to format with dynamic parts, it can end with unexpected results
      contents
    else
      GraphqlQuery.Format.format(contents)
    end
  end
end
