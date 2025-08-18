# GraphqlQuery

![CI](https://github.com/rockneurotiko/graphql_query/actions/workflows/ci.yml/badge.svg)
[![Package](https://img.shields.io/hexpm/v/graphql_query.svg)](https://hex.pm/packages/graphql_query)
[![Documentation](http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat)](https://hexdocs.pm/graphql_query)

<!-- MDOC -->

Elixir tools for **validating, parsing, and formatting GraphQL queries and schemas**, backed by a Rust implementation for performance.
Provides compile-time and runtime validation, schema-aware checks, and Mix formatter integration.

⚠️ **Disclaimer:** This library is still in early development. APIs may change as it evolves.

---

## Table of Contents
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Why This Library?](#why-this-library)
- [Features](#features)
- [Usage](#usage)
  - [~GQL Sigil](#gql-sigil)
  - [gql Macro](#gql-macro)
  - [gql_from_file Macro](#gql_from_file-macro)
- [Schema Support](#schema-support)
  - [Parsing and Validating Schemas](#parsing-and-validating-schemas)
  - [Schema Modules](#schema-modules)
  - [Query Validation Against Schema](#query-validation-against-schema)
- [Formatter Integration](#formatter-integration)
- [Manual API](#manual-api)
- [Roadmap](#roadmap)
- [License](#license)
- [Links](#links)

---



## Quick Start

### Installation

Add `graphql_query` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:graphql_query, "~> 0.3.0"}
  ]
end
```

Fetch deps:

```bash
mix deps.get
```

No Rust installation required — precompiled binaries are used.

### Example: Compile-time Query Validation

```elixir
import GraphqlQuery

# Valid query
~GQL"""
query GetUser($id: ID!) {
  user(id: $id) {
    name
  }
}
"""

# Invalid query → compile-time warning
~GQL"""
query GetUser($unused: String!) {
  user {
    name
  }
}
"""
# warning: GraphQL validation errors:
# Error: unused variable: `$unused` at file.ex:10:1 - variable is never used
```

### Example: Schema Validation

```elixir
defmodule MyApp.Schema do
  use GraphqlQuery.Schema, schema_path: "priv/graphql/schema.graphql"
end

defmodule MyApp.Queries do
  use GraphqlQuery, schema: MyApp.Schema

  def get_user_query do
    ~GQL"""
    query GetUser($id: ID!) {
      user(id: $id) {
        id
        name
        email
      }
    }
    """
  end
end
```

---

## Why This Library?

- **Developer tool**: Focused on **validation, formatting, compile-time and runtime safety**.
- **External APIs integration**: Build and validate queries against external GraphQL APIs. Never miss a deprecated field, a type error in the arguments or a typo in the fields you are fetching.
- **Best match for your tests**: Use in your tests to build and validate queries against any GraphQL schema (external APIs, you own Absinthe schema, ...), catch issues early on development.
- **Not a GraphQL server**: Unlike [Absinthe](https://hex.pm/packages/absinthe), this library does not execute queries.

---

## Features

- ✅ **GraphQL query validation** (syntax, unused vars, fragments, spec compliance)
- ✅ **Schema parsing and validation** (from strings or files)
- ✅ **Schema-aware query validation** (detect invalid fields/types)
- ✅ **Compile-time macros**:
  - `~GQL` sigil for static queries
  - `gql` macro for dynamic queries
  - `gql_from_file` for file-based queries
- ✅ **Query formatting** with consistent indentation
- ✅ **Mix format integration** for `~GQL` sigil, `.graphql` and `.gql` files
- ✅ **Schema modules** with automatic recompilation on schema changes
- ✅ **Flexible validation modes**: compile-time, runtime, or ignore
- ✅ **Manual API**: `GraphqlQuery.Validator.validate`, `GraphqlQuery.Format.format`
- ⚡ Backed by Rust for fast parsing and validation

---

## Usage

### `~GQL` Sigil
- For **static queries only** (no interpolation).
- Validates at compile time.
- [Optional formatter plugin](#formatter-integration).
- Supports modifiers:
  - `i` → ignore warnings
  - `s` → parse as schema

```elixir
import GraphqlQuery

# Valid query
~GQL"""
query GetUser($id: ID!) {
  user(id: $id) {
    name
  }
}
"""

# Ignore warnings
~GQL"""
query GetUser($id: ID!, $unused: String) {
  user(id: $id) { name }
}
"""i

# Parse schema
~GQL"""
type User {
  id: ID!
  name: String!
}
"""s
```

---

### `gql` Macro
- Supports **dynamic queries** with interpolation.
- Options:
  - `evaluate: true` → expand module calls at compile time
  - `runtime: true` → validate at runtime instead of compile time
  - `ignore: true` → skip validation
  - `type: :query | :schema` → Specify if the content shall be validated as query or schema
  - `schema: SchemaModule` → Specify the schema module to validate the query with it

```elixir
defmodule Example do
  use GraphqlQuery

  @fields "name email"

  # Expand module attributes
  def query do
    gql """
    query {
      user { #{@fields} }
    }
    """
  end

  # Expand other module calls
  def query_with_eval do
    gql [evaluate: true], """
    query {
      ...#{OtherModule.fragment_name()}
      #{OtherModule.more_fields()}
    }
    #{OtherModule.fragment()}
    """
  end

  # Runtime validation for local variables
  def query_runtime(user_id) do
    gql [runtime: true], """
    query {
      user(id: #{user_id}) { name }
    }
    """
  end
end
```

---

### `gql_from_file` Macro
- Load queries or schemas from `.graphql` or `.gql` files.
- Validates at compile time.
- Tracks file changes for recompilation.
- Options:
  - `ignore: true` → skip validation
  - `type: :query | :schema` → Specify if the content shall be validated as query or schema
  - `schema: SchemaModule` → Specify the schema module to validate the query with it

Example project structure:

```text
priv/
├── graphql/
|   ├── schema.graphql
|   ├── get_user.graphql
|   └── create_user.gql
```

```elixir
defmodule MyApp.Schema do
  use GraphqlQuery.Schema, schema_path: "priv/graphql/schema.graphql"
end

defmodule MyApp.Queries do
  use GraphqlQuery, schema: MyApp.Schema

  @get_user_query gql_from_file "priv/graphql/get_user.graphql"

  def get_user_query, do: @get_user_query

  def create_user_mutation do
    gql_from_file "priv/graphql/create_user.gql", schema: MyApp.Schema
  end
end
```

---

## Schema Support

### Parsing and Validating Schemas

With macros:

```elixir
schema = gql [type: :schema], """
type User { id: ID! name: String! }
type Query { user(id: ID!): User }
"""

schema = gql_from_file "path/to/schema.graphql", type: :schema
```

Or with sigil:

```elixir
~GQL"""
type User { id: ID! name: String! }
type Query { user(id: ID!): User }
"""s
```

---

### Schema Modules
- Parses and validates schema at compile time
- Provides `schema/0` and `schema_path/0`
- Recompiles when schema file changes

Automatically implement the behaviour with a schema file:

```elixir
defmodule MyApp.Schema do
  use GraphqlQuery.Schema, schema_path: "priv/graphql/schema.graphql"
end
```

Or manually implement the behaviour:

```elixir
defmodule MyApp.Schema do
  use GraphqlQuery.Schema

  @impl GraphqlQuery.Schema
  def schema do
    ~GQL"""
    type User { id: ID! name: String! }
    type Query { user(id: ID!): User }
    """s
  end
end
```

---

### Query Validation Against Schema
**Per-query validation:**

```elixir
gql [schema: MyApp.Schema], """
query GetUser($id: ID!) {
  user(id: $id) { name email }
}
"""
```

**Module-level schema:**

```elixir
defmodule MyApp.Queries do
  use GraphqlQuery, schema: MyApp.Schema

  def get_users do
    ~GQL"""
    query { users { id name } }
    """
  end

  def get_user(user_id) do
    # It is recommended to use GraphQL variables, this is just an example to showcase runtime validation with schema
    gql [runtime: true], """
    query GetUserById { user(id: "#{user_id}") { name } }
    """
  end
end
```

---

## Formatter Integration

Add to `.formatter.exs`:

```elixir
[
  inputs: ["{lib,test,priv}/**/*.{ex,exs,graphql,gql}"],
  plugins: [GraphqlQuery.Formatter],
  import_deps: [:graphql_query]
]
```

Now `mix format` will:
- Format `.graphql` and `.gql` files
- Format `~GQL` sigils in Elixir code

---

## Manual API

```elixir
# Validate query
GraphqlQuery.Validator.validate("""
query GetUser($id: ID!) { user(id: $id) { name } }
""")
# => :ok

# Invalid query
GraphqlQuery.Validator.validate("query T($unused: String) { field }")
# => {:error, [%GraphqlQuery.Native.ValidationError{}]}

# Validate a schema
GraphqlQuery.Validator.validate(schema, schema_path, nil, :schema)

# Validate a query with a schema (schema_module must implement GraphqlQuery.Schema)
GraphqlQuery.Validator.validate(query, query_path, schema_module, :query)

# Format query
GraphqlQuery.Format.format("query GetUser($id: ID!){user(id:$id){name email}}")
# => """
# query GetUser($id: ID!) {
#   user(id: $id) {
#     name
#     email
#   }
# }
# """
```

---

## Roadmap

### Planned

- [ ] Configure schemas with remote URLs to fetch, and have a mix task to check if the content differs
- [ ] Optional compile-time validation via Mix task
- [ ] Think on fragments and if we need specific support for named fragments

### Done

- [x] Validate queries with sigil
- [x] Format queries with formatter plugin
- [x] `gql` macro for dynamic queries
- [x] `gql_from_file` macro for file-based queries
- [x] Schema parsing and validation

---



## License
Beerware 🍺 — do whatever you want with it, but if we meet, buy me a beer.

<!-- MDOC -->

---

## Links
- [GitHub](https://github.com/rockneurotiko/graphql_query)
- [Hex.pm](https://hex.pm/packages/graphql_query)
- [Docs](https://hexdocs.pm/graphql_query)
