# Elixir Macros

By default, GraphqlQuery will try to validate the GraphQL documents in compile time. That's one of the main features!

But, there are some limitations in what Elixir Macros can or cannot access on compile time.

Let's see some examples on what can be done, and what can't be done.

When GraphqlQuery detect that we can't expand some options, it will automatically use runtime validation.

If you don't want to do runtime validation, you either fix the compile values, or set ignore for the module:

`use GraphqlQuery, ignore: true`

If you want to do runtime validation and have weird compile access, but don't want the warning, you can set runtime for the module:

`use GraphqlQuery, runtime: true`

## ✅ Access to your own module attributes in methods.

In Elixir, module attributes and code outside of code blocks are compiled first, and then the method's bodies are compiled.
That means that from inside a method we can access the module attributes.

```elixir
defmodule Test do
  use GraphqlQuery

  @fragment ~GQL"..."f

  def query do
    gql [fragments: [@fragment]], ""
  end
end

```

## ❌ Access to your own module attributes from other module attributes

In Elixir, module attributes and code outside of code blocks are compiled first, and they don't have access to the content of other "peers" at the same level.
That means that we can't reference other module attributes in compile time.

```elixir
defmodule Test do
  use GraphqlQuery

  @fragment ~GQL"..."f

  @query gql [fragments: [@fragment]], ""
end
```

## ✅ Access to other module public methods, as long as their value is known at compile time.

GraphqlQuery will detect the usage of other modules and will wait for their compilation, and if the method's value is static, we can access from the macro:

```elixir
defmodule Fragments do
  use GraphqlQuery

  @fragment ~GQL"..."f
  def fragment, do: @fragment

  def fragment2, do: ~GQL"..."f
end

defmodule Test do
  use GraphqlQuery

  @fragment Fragments.fragment()

  def query do
    gql [fragments: [@fragment, Fragments.fragment2()]], ""
  end
end
```

## ❌ Access variable values

This is probably the most shocking one. But you can't access the variable values in your method or module, even if they are a static value like a string.

```elixir
defmodule Test do
  use GraphqlQuery

  # This is obvious that we don't have the value on compile time
  def get_user_by_id(user_id) do
    gql """
    query User {
      user(id: #{user_id}) { id name }
    }
    """
  end

  # But this is not that obvious, we can't access *any* variable at all
  def get_users do
    user_id = "123"

    gql """
    query User {
      user(id: #{user_id}) { id name }
    }
    """
  end
end
```
