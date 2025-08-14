# GraphqlQuery

![CI](https://github.com/rockneurotiko/graphql_query/actions/workflows/ci.yml/badge.svg)
[![Documentation](http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat)](https://hexdocs.pm/graphql_query)
[![Package](https://img.shields.io/hexpm/v/graphql_query.svg)](https://hex.pm/packages/graphql_query)

<!-- MDOC -->

Elixir tools for validating and formatting GraphQL queries, backed by a Rust implementation for parsing and validation.

## Disclaimer

This library is still in early phase. While I iterate on the best approach to implement the library, you can expect API changes.

## What This Library Does

GraphqlQuery provides:

- **GraphQL query validation** - Comprehensive validation including syntax, unused variables, and GraphQL specification compliance
- **Query formatting** - Pretty-print GraphQL queries with consistent indentation and structure
- **Compile-time validation** - Use the `~GQL` sigil for static queries or the `gql` macro for dynamic queries with compile-time validation
- **Mix format integration** - Format `~GQL` sigil, `.graphql` and `.gql` files with `mix format`

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

Import to use both the sigil and macro for GraphQL query validation:

``` elixir
# Use evaluate option to expand function calls at compile time
defmodule T do
  @filter "id: $id"

  def query do
    gql """
    query GetUser($id: String) {
      user(#{@filter}) {
        name
      }
    }
    """
  end
end


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

### `~GQL` Sigil
- For **static queries only** - no dynamic parts allowed
- Validates at compile time with helpful warnings
- Formatter plugin will format it automatically when executing `mix format`

#### `~GQL` Sigil Examples

``` elixir
import GraphqlQuery

# Correct query
~GQL"""
query GetUser($id: ID!) {
  user(id: $id) {
    name
  }
}
"""

# Warnings will be printed on compile time, variable is unused
~GQL"""
query GetUser($id: ID!, $unused: String) {
  user(id: $id) {
    name
  }
}
"""

# You can ignore the warnings with the "i" sigil modifier
~GQL"""
query GetUser($id: ID!, $unused: String) {
  user(id: $id) {
    name
  }
}
"""i

# If you try to use dynamic parts, it will print a warning too:
~GQL"""
query GetUser($id: ID!) {
  user(id: $id) {
    name
    #{@data}
  }
}
"""
```

### `gql_from_file` Macro

`Load and validate GraphQL queries from external files at compile time. This macro is ideal for organizing complex queries in separate `.graphql` or `.gql` files while still getting compile-time validation.

#### Features:
- **File-based queries** - Keep GraphQL queries in separate files for better organization
- **Compile-time validation** - Validates the file contents at compile time
- **File formatting** - If the formatter plugin is setup, your GraphQL files will be formatted.
- **Dependency tracking** - Automatically recompile modules when the GraphQL file changes

#### Options:
- `ignore: true` - Skip validation and warnings for the file contents

The macro automatically adds the file as an external resource, so your application will recompile when the GraphQL file changes, but it does not validate the contents.

#### Usage:

The path is relative to your application initial directory, not the file's directory

#### Example file structure:
```
your_app/
├── lib/
│   └── your_app.ex
└── priv/
    └── graphql/
        ├── get_user.graphql
        └── create_user.gql
```

#### `priv/graphql/get_user.graphql`:
```graphql
query GetUser($id: ID!) {
  user(id: $id) {
    id
    name
    email
    createdAt
  }
}
```

#### `priv/graphql/create_user.gql`:
```graphql
mutation CreateUser($id: ID!, name: String!, email: String!) {
  createUser(id: $id, name: $name, email: $email) {
    user {
      id
      name
      email
      createdAt
    }
  }
}
```

#### Using in Elixir:
```elixir
defmodule MyApp.Queries do
  import GraphqlQuery

  # You can save the queries in module attributes
  @get_user_query gql_from_file "priv/graphql/get_user.graphql"

  def get_user_query do
    @get_user_query
  end

  def create_user_mutation do
    gql_from_file "priv/graphql/create_user.gql"
  end
end
```

### `gql` Macro
- Handles **dynamic queries** with string interpolation
- Options:
  - `evaluate: true` - Try to evaluate function calls at compile time
  - `runtime: true` - Validate at runtime instead of compile time
  - `ignore: true` - Skip validation and warnings

This macro allow you to try to expand variables dynamic interpolation on compile time.

By default, it is able to expand static module attributes, like `@user_id "123"`

It can evaluate calls to other modules, like `#{OtherModule.fields()}`, to try to evaluate calls you can pass the option to the macro:

```elixir
gql [evaluate: true], """
query { #{OtherModule.fields()} }
"""
```

The evaluation only work with calls to other module methods and if they have static data.
If the evaluation can't be made, you can still delay the query validation to runtime:

``` elixir
gql [runtime: true], """
query { #{OtherModule.fields()} }
"""
```

In runtime validation, it will just try to validate the query whenever this is trying to be used, and if there is a warning it will use `Logger.warning`

And if you don't want to have runtime validation, you can ignore the warning, they query will be built
correctly on runtime, just not validated:

```elixir
gql [ignore: true], ...
```

All this options can be set in `gql` calls, or to all the module when `using` the library:

```
# Always try to evaluate, and if the evaluation fails, delay the validation to runtime
use GraphqlQuery, evaluate: true, runtime: true
```

#### What can a macro expand

The `gql` macro will try to expand by default own module attributes.

With `evaluate: true` option, it can expand method calls to other modules, as long as they are static data.

It will never be able to expand local variables or local method calls, that's how the macro compilation works.

Examples of common cases:

```elixir
defmodule Expansions do
    use GraphqlQuery

    # ✅ Module attributes

    @fields "name surname"

    def local_attribute do
        gql """
        query T {
            users {
                #{@fields}
            }
        }
        """
    end

    # ✅ Other GQL or gql results

    @user_fragment ~GQL"""
    fragment UserFields on User {
        name
        email
    }
    """i # We ignore the unused fragment error, but we get automatic formatting

    def gql_results do
        gql """
        query {
            user {
                ...UserFields
            }
        }
        #{@user_fragment}
        """
    end

    # ✅ Other module calls with static data with evaluate: true

    defmodule Test do
        def fragment_name, do: "UserIdentifier"
        def fragment do
            ~GQL"""
            fragment UserIdentifier on User {
                id
                email
            }
            """i
        end

        def more_fields, do: ["name", "surname"] |> Enum.join("\n")
    end

    def module_static do
        gql [evaluate: true], """
        query T {
            ...#{Expansions.Test.fragment_name()}
            #{Expansions.Test.more_fields()}
        }

        #{Expansions.Test.fragment()}
        """
    end

    # ❌ Local variables, not even evaluating

    def local_variable do
        fields = "name username"

        gql [evaluate: true], """
        query T {
            #{fields}
        }
        """
    end

    # ✅ Validate in runtime
    # If we need local variables, we can delegate to runtime the validation, or ignore the warnings
    def local_variable_ok(user_id) do
        fields = ~w(user name surname)

        # Or [ignore: true] if you don't want to validate
        gql [runtime: true], """
        query T {
            user(id: #{user_id}) {
                #{fields}
            }
        }
        """
    end
end
```


### Formatter

The library provide a formatter plugin and the ability to ignore parenthesis on the macro calls

#### Plugin
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
- Format GraphQL files (`.graphql`, `.gql`) in your input files
- Format `~GQL` sigils in your Elixir code

#### Extension
To use the macros without parenthesis, you can add the library to the formatter import_deps in your `.formatter.exs`:

```
[
  # ... Existing config
  import_deps: [:graphql_query]
]
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
- [X] Add `gql_from_file` macro that allows to import a graphql macro from a file
- [ ] Manage graphql schemas, and optionally use it to parse and validate queries
- [ ] Optional validation in compile time for static queries, and instead provide a mix task to validate all queries

<!-- MDOC -->

## License

Beerware

## Links

- [GitHub](https://github.com/rockneurotiko/graphql_query)
- [Hex.pm](https://hex.pm/packages/graphql_query)
