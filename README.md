# GraphqlQuery

![CI](https://github.com/rockneurotiko/graphql_query/actions/workflows/ci.yml/badge.svg)
[![Documentation](http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat)](https://hexdocs.pm/graphql_query)
[![Package](https://img.shields.io/hexpm/v/graphql_query.svg)](https://hex.pm/packages/graphql_query)

<!-- MDOC -->

Elixir tools for validating and formatting GraphQL queries, backed by a Rust implementation for parsing and validation.

## What This Library Does

GraphqlQuery provides:

- **GraphQL query validation** - Comprehensive validation including syntax, unused variables, and GraphQL specification compliance
- **Query formatting** - Pretty-print GraphQL queries with consistent indentation and structure
- **Compile-time validation** - Use the `~GQL` sigil for static queries or the `gql` macro for dynamic queries with compile-time validation
- **Mix format integration** - Format `.graphql` and `.gql` files with `mix format`

The library combines Elixir's developer-friendly API with Rust's parsing performance, using RustlerPrecompiled for easy installation without requiring users to have Rust installed.

## Installation

Add `graphql_query` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:graphql_query, "~> 0.1.0"}
  ]
end
```

Run `mix deps.get` to install.

No additional setup required - the library uses precompiled Rust binaries via RustlerPrecompiled.

## Usage

### The `~GQL` Sigil and `gql` Macro

Import to use both the sigil and macro for GraphQL query validation:

```elixir
import GraphqlQuery

# Static query with ~GQL sigil - validates at compile time
query = ~GQL"""
query GetUser($id: ID!) {
  user(id: $id) {
    name
    email
    posts {
      title
      content
      createdAt
    }
  }
}
"""

# Dynamic query with gql macro - can expand variables at compile time
user_id = "123"
dynamic_query = gql "query GetUser { user(id: \"#{user_id}\") { name } }"

# Use evaluate option to expand function calls at compile time
get_user_id = fn -> "456" end
compile_time_query = gql [evaluate: true], "query GetUser { user(id: \"#{get_user_id.()}\") { name } }"

# Invalid query - shows compile warning
invalid_query = ~GQL"""
query GetUser($unused: String!) {
  user {
    name
  }
}
"""
# warning: GraphQL validation errors:
# Error: unused variable: `$unused` at /path/to/file.ex:10:1 - variable is never used
```

#### `~GQL` Sigil
- For **static queries only** - no dynamic parts allowed
- Validates at compile time with helpful warnings
- Returns the query string for runtime use

#### `gql` Macro
- Handles **dynamic queries** with string interpolation
- Options:
  - `evaluate: true` - Try to evaluate function calls at compile time
  - `runtime: true` - Validate at runtime instead of compile time
  - `ignore: true` - Skip validation and warnings
- Expands variables and validates when possible at compile time

### GraphQL Query Examples

**Simple query:**
```graphql
{
  user {
    id
    name
  }
}
```

**Query with variables:**
```graphql
query GetUserPosts($userId: ID!, $limit: Int = 10) {
  user(id: $userId) {
    name
    posts(limit: $limit) {
      id
      title
      content
      publishedAt
    }
  }
}
```

**Mutation:**
```graphql
mutation CreatePost($input: PostInput!) {
  createPost(input: $input) {
    id
    title
    author {
      name
    }
  }
}
```

**Query with fragments:**
```graphql
fragment UserInfo on User {
  id
  name
  email
}

query GetUsers {
  users {
    ...UserInfo
    posts {
      title
    }
  }
}
```

### Formatter Plugin

To automatically format the `~GQL` sigil contents, `.graphql` and `.gql` files with `mix format`, add the plugin to your `.formatter.exs`:

```elixir
[
  inputs: [
    # ... Existing inputs
    "{lib/test/priv}/**/*.{graphql,gql}"
  ],
  plugins: [GraphqlQuery.Formatter]
]
```

Now `mix format` will:
- Format GraphQL files (`.graphql`, `.gql`) in your project
- Format `~GQL` sigils in your Elixir code

Example formatting:

**Before:**
```graphql
query GetUser($id: ID!){user(id: $id){name email posts{title content}}}
```

**After:**
```graphql
query GetUser($id: ID!) {
  user(id: $id) {
    name
    email
    posts {
      title
      content
    }
  }
}
```

### Manual Validation and Formatting

```elixir
# Validate a GraphQL query
GraphqlQuery.validate("""
query GetUser($id: ID!) {
  user(id: $id) {
    name
    email
  }
}
""")
# => :ok

# Invalid query returns detailed errors
GraphqlQuery.validate("query T($unused: String) { field }")
# => {:error, ["Error: unused variable: `$unused` at document.graphql:1:9 - variable is never used"]}

# Format a query
GraphqlQuery.format("query GetUser($id: ID!){user(id: $id){name email}}")
# => """
# query GetUser($id: ID!) {
#   user(id: $id) {
#     name
#     email
#   }
# }
# """
```

## Features

- [X] Validate graphql queries with a sigil
- [X] Format graphql queries with a formatter plugin
- [X] Add `gql` macro that allows expanding compile time variables and dynamic parts
- [ ] Manage graphql schemas, and optionally use it to parse and validate queries
- [ ] Optional validation in compile time, and instead provide a mix task to validate all queries

<!-- MDOC -->

## License

Beerware

## Links

- [GitHub](https://github.com/rockneurotiko/graphql_query)
- [Hex.pm](https://hex.pm/packages/graphql_query)
