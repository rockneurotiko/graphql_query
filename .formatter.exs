# Used by "mix format"
local_macros = [gql: 1, gql: 2, gql_from_file: 1, gql_from_file: 2]

[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs,graphql,gql}"
  ],
  plugins: [GraphqlQuery.Formatter],
  locals_without_parens: local_macros,
  export: [local_without_parens: local_macros]
]
