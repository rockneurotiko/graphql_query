<h1><p align="center"><img src="graphql_query.png" alt="GraphQL Query" width="350"></p></h1>

![CI](https://github.com/rockneurotiko/graphql_query/actions/workflows/ci.yml/badge.svg)
[![Package](https://img.shields.io/hexpm/v/graphql_query.svg)](https://hex.pm/packages/graphql_query)
[![Documentation](http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat)](https://hexdocs.pm/graphql_query)

<!-- MDOC -->

GraphQL Query provides a library for **validating, parsing, and formatting GraphQL queries and schemas**

⚠️ **Disclaimer:** This library is still in early development. APIs may change as it evolves.

---

## Table of Contents

- [Why This Library?](#why-this-library)
- [Features](#features)
- [Quick Start](#quick-start)
  - [Installation](#installation)
  - [Examples](#examples)
- [Usage](#usage)
  - [~GQL Sigil](#gql-sigil)
  - [gql_from_file Macro](#gql_from_file-macro)
  - [gql Macro](#gql-macro)
  - [document_with_options Macro](#document_with_options-macro)
- [Use the documents in HTTP Requests](#use-the-documents-in-http-requests)
- [Fragment support](#fragment-support)
  - [Define fragments](#define-fragments)
  - [Use fragments](#use-fragments)
- [Schema Support](#schema-support)
  - [Parsing and Validating Schemas](#parsing-and-validating-schemas)
  - [Schema Modules](#schema-modules)
  - [Document Validation Against Schema](#document-validation-against-schema)
- [Formatter Integration](#formatter-integration)
- [Manual API](#manual-api)
- [Roadmap](#roadmap)
- [License](#license)
- [Links](#links)

---

## Why This Library?

- **Developer tool**: Focused on **validation, formatting, compile-time and runtime safety**.
- **External APIs integration**: Build and validate queries against external GraphQL APIs. Never miss a deprecated field, a type error in the arguments or a typo in the fields you are fetching.
- **Best match for your tests**: Use in your tests to build and validate queries against any GraphQL schema (external APIs, you own Absinthe schema, ...), catch issues early on development.
- **Not a GraphQL server**: [Absinthe](https://hex.pm/packages/absinthe) is for building GraphQL servers. `GraphqlQuery` is for validating and formatting queries against schemas (including external APIs). They complement each other perfectly - you can extract your Absinthe schema and use it to validate client queries on tests.

---

## Features

- ✅ **GraphQL queries and mutations validation** (syntax, unused vars, fragments, spec compliance)
- ✅ **Schema parsing and validation** (from strings or files)
- ✅ **Fragment support** with composition, reusability, and validation
- ✅ **Schema-aware query, mutation and fragments validation** (detect invalid fields/types)
- ✅ **Compile-time macros**:
  - `~GQL` sigil for static queries
  - `gql_from_file` for file-based queries
  - `gql` macro for dynamic queries
  - `document_with_options` for applying options to multiple macros
- ✅ **Query formatting** with consistent indentation
- ✅ **Mix format integration** for `~GQL` sigil, `.graphql` and `.gql` files
- ✅ **Schema modules** with automatic recompilation on schema changes
- ✅ **Absinthe schema integration** for validating queries against existing Absinthe schemas
- ✅ **Flexible validation modes**: compile-time, runtime, or ignore
- ✅ **JSON encoding support** for Document structs (JSON/Jason protocols)
- ⚡ Backed by Rust for fast parsing and validation

---

## Quick Start

### Installation

Add `graphql_query` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:graphql_query, "~> 0.3"}
  ]
end
```

Fetch deps:

```bash
mix deps.get
```

No Rust installation required — precompiled binaries are used.

### Examples

You can find more examples in the [Cheatsheet](cheatsheet.cheatmd), here is a little compilation.

#### Example: Compile-time Document Validation

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

#### Example: Schema Validation

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

#### Example: Usage in requests

```elixir
query = gql [fragments: [@user_fragment]], """
query { ... }
"""

user = "1"
user_query = GraphqlQuery.Document.add_variable(query, :id, user)
Req.post!("/api", json: user_query)
```

---

## Usage

### `~GQL` Sigil
- For **static queries only** (no interpolation).
- Validates at compile time.
- [Optional formatter plugin](#formatter-integration).
- Supports modifiers, the modifiers are applied at the end of the string: `~GQL""rf`:
  - `i` → Ignore warnings
  - `r` -> Validate on runtime
  - `s` → Parse as schema
  - `q` → Parse as query (this is the default behaviour)
  - `f` → Parse as fragment

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

# Parse fragment
~GQL"""
fragment UserData on User {
  id
  name
}
"""f

# Delegate validation to runtime
# Try not to use it, but if you need it you have the option
~GQL"""
query GetUser($id: ID!) {
  user(id: $id) {
    ...UserData
  }
}
"""r |> GraphqlQuery.Document.add_fragment(user_data)

```

---

### `gql_from_file` Macro
- Load queries or schemas from `.graphql` or `.gql` files.
- Validates at compile time.
- Tracks file changes for recompilation.
- Options:
  - `ignore: true` → skip validation
  - `type: :query | :schema | :fragment` → Specify if the content shall be validated as query, schema or fragment
  - `schema: SchemaModule` → Specify the schema module to validate the query or fragment with
  - `fragments: [GraphqlQuery.Fragment.t()]` → Add reusable fragments to queries

Example project structure:

```
priv/
├── graphql/
|   ├── schema.graphql
|   ├── get_user.graphql
|   └── create_user.gql
|   └── user_fragment.gql
```

```elixir
defmodule MyApp.Schema do
  use GraphqlQuery.Schema, schema_path: "priv/graphql/schema.graphql"
end

defmodule MyApp.Queries do
  use GraphqlQuery, schema: MyApp.Schema

  @user_fragment gql_from_file "priv/graphql/user_fragment.gql", type: :fragment

  def get_user_query do
    gql_from_file "priv/graphql/get_user.graphql", fragments: [@user_fragment]
  end

  def create_user_mutation do
    gql_from_file "priv/graphql/create_user.gql", schema: MyApp.Schema
  end
end
```

---

### `gql` Macro
- Supports **dynamic queries** with interpolation.
- Options:
  - `evaluate: true` → expand module calls at compile time
  - `runtime: true` → validate at runtime instead of compile time
  - `ignore: true` → skip validation
  - `type: :query | :schema | :fragment` → Specify if the content shall be validated as query, schema or fragment
  - `schema: SchemaModule` → Specify the schema module to validate the query or fragment with
  - `fragments: [GraphqlQuery.Fragment.t()]` → Add reusable fragments to queries

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

  # Specify fragments for the query
  def query_with_fragments do
    gql [fragments: [OtherModule.fragment()]], """
    query {
      users {
        ...UserFragment
      }
    }
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

### `document_with_options` Macro

- Apply **common options** to all GraphqlQuery macros and sigils within a block
- **Key feature**: Enables the `~GQL` sigil to work with complex options like `:schema` and `:fragments`
- Supports all the same options as individual macros
- Options are merged with precedence ((explicit macro options | sigil modifiers) > `document_with_options` > module defaults)

The main use case for the macro `document_with_options` is to  **use fragments and schema validation with sigils**.
The `~GQL` sigil doesn't support schema or fragments options directly, but `document_with_options` enables it:

```elixir
# This won't work - sigils don't support schema options
~GQL"""
query GetUser { user { id name } }
"""[schema: MySchema]  # ❌ Invalid syntax

# This works perfectly
document_with_options schema: MySchema do
  ~GQL"""
  query GetUser { user { ...UserFragment } }
  """  # ✅ Schema validation applied
end
```

```elixir
defmodule MyApp.Schema do
  use GraphqlQuery.Schema, schema_path: "priv/schema.graphql"
end

defmodule MyApp.Queries do
  use GraphqlQuery, schema: MyApp.Schema

  @user_fragment ~GQL"""
  fragment UserFragment on User {
    id
    name
  }
  """f

  def user_query do
    document_with_options fragments: [@user_fragment] do
      ~GQL"""
      query GetUser($id: ID!) {
        user(id: $id) {
          ...UserFragment
        }
      }
      """
    end
  end
end
```

---

## Use the documents in HTTP requests

At the end, we want to build GraphQL queries to do requests to the GraphQL server.

To make it easy, the GraphQL.Document struct returned by `~GQL`, `gql_from_file` and `gql` implement the protocol for the standard library [`JSON`](https://hexdocs.pm/elixir/JSON.html) and for [`Jason`](https://hexdocs.pm/jason/Jason.html).

To use queries in requests, you can directly put the query document in the body if the library supports JSON encoding, or manually call `JSON.encode!(query)` or `Jason.encode!(query)` to get the request body as a string.

The encoding build a json such as `{"query": "document", "variables": {}}`. The document is the query or mutation with the fragments (if any) at the end.

Example with [`Req`](https://github.com/wojtekmach/req) and [`GraphQLZero` mock server](https://graphqlzero.almansi.me):

```elixir
base_query = ~GQL"""
query($id: ID!) {
  user(id: $id) {
    id
    username
    email
    address {
      geo {
        lat
        lng
      }
    }
  }
}
"""
# base_query is a %GraphqlQuery.Document{} struct

# We add variables to create a new document with that information
user_query = GraphqlQuery.Document.add_variable(base_query, :id, "1")

Req.post!("https://graphqlzero.almansi.me/api", json: user_query).body

# %{
#   "data" => %{
#     "user" => %{
#       "address" => %{"geo" => %{"lat" => -37.3159, "lng" => 81.1496}},
#       "email" => "Sincere@april.biz",
#       "id" => "1",
#       "username" => "Bret"
#     }
#   }
# }

```

---

## Fragment support

You can define your fragments and use them with the macros.

### Define fragments

```elixir
# With sigil
fragment = ~GQL"""
fragment UserFragment on User { id name }
"""f

# With macro
fragment = gql [type: :fragment], """
fragment UserFragment on User { id name }
"""f

# From file
fragment = gql_from_file "fragment.graphql", type: :fragment
```

### Use fragments

```elixir
# With sigils you have to use the global module registration, or manually set them and validate on runtime:

defmodule UserQuery do
  use GraphqlQuery, fragments: [MyFragments.user_fragment()], schema: UserSchema

  # Use the fragments registered for the module.
  def query do
    ~GQL"""
    query GetUser($id: ID!) {
      user(id: $id) {
        ...UserFragment
      }
    }
    """
  end

  # Evaluate at runtime, and add the fragments later instead of using the global ones
  def runtime_query do
    query = ~GQL"""
    query GetUser($id: ID!) {
      user(id: $id) {
        ...UserFragment
      }
    }
    """r

    GraphqlQuery.Document.add_fragment(query, MyFragments.user_fragment())
  end
end


# With the gql and gql_from_file macros, you can use the module fragments, or per-query fragments:

gql [fragments: [MyFragments.user_fragment()]], """
    query GetUser($id: ID!) {
      user(id: $id) {
        ...UserFragment
      }
    }
"""

gql_from_file "query.graphql", fragments: [MyFragments.user_fragment()]
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

#### From GraphQL Files

Automatically implement the behaviour with a schema file:

```elixir
defmodule MyApp.Schema do
  use GraphqlQuery.Schema, schema_path: "priv/graphql/schema.graphql"
end
```

#### From Absinthe Schemas

Automatically extract schema from existing Absinthe schema modules, really useful specially for testing:

```elixir
defmodule MyApp.Schema do
  use GraphqlQuery.Schema, absinthe_schema: MyAppWeb.Graphql.Schema
end
```

#### Manual Implementation

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

  @impl GraphqlQuery.Schema
  def schema_path, do: nil
end
```

---

### Document Validation Against Schema

You can validate against the schema any document (queries, mutations or  fragments)

**Per-document validation:**

```elixir
gql [schema: MyApp.Schema], """
query GetUser($id: ID!) {
  user(id: $id) { name email }
}
"""

gql_from_file "path.graphql", [schema: MyApp.Schema]
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

You shouldn't need to use the manual API, but if you need to, you can do everything yourself.

Check the documentation of these modules if you want to know more about the manual API:
- [GraphqlQuery.Document](https://hexdocs.pm/graphql_query/GraphqlQuery.Document.html)
- [GraphqlQuery.Fragment](https://hexdocs.pm/graphql_query/GraphqlQuery.Fragment.html)
- [GraphqlQuery.Validator](https://hexdocs.pm/graphql_query/GraphqlQuery.Validator.html)
- [GraphqlQuery.Format](https://hexdocs.pm/graphql_query/GraphqlQuery.Format.html)

---

## Roadmap

### Planned

- [ ] When validation error, try to detect if it's in a fragment, and if it's an "imported" fragment, print the error in the fragment's location
- [ ] Configure schemas with remote URLs to fetch, and have a mix task to check if the content differs
- [ ] Optional compile-time validation via Mix task
- [ ] Fix line reporting on validation errors on gql on expanded code


### Done

- [x] Validate queries with sigil
- [x] Format queries with formatter plugin
- [x] `gql` macro for dynamic queries
- [x] `gql_from_file` macro for file-based queries
- [x] Schema parsing and validation
- [x] Custom Document and Fragment representation, with implementation for to_string and json with JSON and Jason
- [x] Allow to set fragments in individual queries or per-module (`document_with_options` macro)
- [x] Extract document info, and calculate if possible name and signature
- [x] Improve non-compile time options detection and fallback to runtime/ignore
- [x] GraphqlQuery.Schema with Absinthe schema

---

## License
Beerware 🍺 — do whatever you want with it, but if we meet, buy me a beer. (This is essentially MIT-like. Use it freely, but if we meet, buy me a beer)

<!-- MDOC -->

---

## Links
- [GitHub](https://github.com/rockneurotiko/graphql_query)
- [Hex.pm](https://hex.pm/packages/graphql_query)
- [Docs](https://hexdocs.pm/graphql_query)
