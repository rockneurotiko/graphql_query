defmodule GraphqlQuery do
  @external_resource "README.md"

  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  alias __MODULE__.{Parser, Document, Validator}

  @doc """
  Sets up the module to use GraphQL query macros and validation.

  ## Options

    * `:schema` - Schema module implementing GraphqlQuery.Schema behaviour
    * `:runtime` - Whether to validate queries at runtime (default: false)
    * `:ignore` - Whether to ignore validation errors (default: false)
    * `:evaluate` - Whether to try evaluating dynamic parts at compile time (default: false)
    * `:fragments` - List of fragments to include in queries (default: [])

  ## Examples

      defmodule MyApp.Queries do
        use GraphqlQuery, schema: MyApp.Schema

        def get_user do
          ~GQL"query { user { id name } }"
        end
      end

  """
  defmacro __using__(opts) do
    module = __CALLER__.module
    schema = opts[:schema]
    opts = GraphqlQuery.MacroOptions.validate!(Keyword.delete(opts, :schema))

    if schema do
      loaded_schema = ensure_module_loaded!(schema)
      behaviours = get_module_behaviours(loaded_schema)

      if GraphqlQuery.Schema not in behaviours do
        raise ArgumentError,
              "Schema module #{inspect(schema)} must implement GraphqlQuery.Schema behaviour"
      end
    end

    Module.put_attribute(module, :__graphql_query__runtime, opts.runtime)
    Module.put_attribute(module, :__graphql_query__ignore, opts.ignore)
    Module.put_attribute(module, :__graphql_query__evaluate, opts.evaluate)
    Module.put_attribute(module, :__graphql_query__schema, schema)
    Module.put_attribute(module, :__graphql_query__fragments, opts.fragments)

    quote do
      import GraphqlQuery
    end
  end

  defp get_module_behaviours(module) do
    module.module_info()[:attributes]
    |> Enum.filter(fn {k, _} -> k == :behaviour end)
    |> Enum.flat_map(fn {_, behaviours} -> behaviours end)
  end

  defmacro document_with_options(opts, do: block) do
    GraphqlQuery.MacroOptions.validate!(opts)

    modified_block = Macro.prewalk(block, fn ast -> add_extra_opts_to_ast(ast, opts) end)

    quote do
      unquote(modified_block)
    end
  end

  # This is used like:
  # document_with_options ~GQL"", ignore: true
  # But I don't really like this syntax, let's keep it commented out for now
  # defmacro document_with_options(ast, opts) do
  #   GraphqlQuery.MacroOptions.validate!(opts)
  #   ast = add_extra_opts_to_ast(ast, opts)

  #   quote do
  #     unquote(ast)
  #   end
  # end

  defp add_extra_opts_to_ast(ast, opts) do
    case ast do
      {:sigil_GQL, meta, params} ->
        {:sigil_GQL, meta, params ++ [opts]}

      {:gql, meta, [data]} ->
        {:gql, meta, [opts, data]}

      {:gql, meta, [current_opts, data]} ->
        new_opts = Keyword.merge(opts, current_opts)
        {:gql, meta, [new_opts, data]}

      {:gql_from_file, meta, [data]} ->
        {:gql_from_file, meta, [data, opts]}

      {:gql_from_file, meta, [data, current_opts]} ->
        new_opts = Keyword.merge(opts, current_opts)
        {:gql_from_file, meta, [data, new_opts]}

      other ->
        other
    end
  end

  @doc """
  Loads and validates GraphQL queries from external files.

  Automatically tracks file dependencies for recompilation and validates
  the loaded content at compile time.

  ## Options

    * `:type` - Document type (:query, :schema, :fragment) (default: :query)
    * `:ignore` - Skip validation (default: false)
    * `:schema` - Schema module for validation (default: module schema if set)
    * `:fragments` - List of fragments to include (default: [])

  ## Examples

      # Load a query file
      query = gql_from_file("priv/queries/get_user.graphql")

      # Load a fragment with schema validation
      fragment = gql_from_file("priv/fragments/user.gql",
                               type: :fragment,
                               schema: MyApp.Schema)

      # Load schema
      schema = gql_from_file("priv/schema.graphql", type: :schema)

  """
  defmacro gql_from_file(file_path, opts \\ []) do
    Module.put_attribute(__CALLER__.module, :external_resource, file_path)
    caller = __CALLER__

    GraphqlQuery.MacroOptions.validate!(opts)

    ignore? = get_option(opts, :ignore, false, caller)
    runtime_validation? = get_option(opts, :runtime, false, caller)
    type = get_option(opts, :type, :query, caller)
    schema_module = get_schema_module(opts, caller)
    fragments = get_option(opts, :fragments, [], caller)

    contents = File.read!(file_path)

    warn_location = [file: file_path]

    query_opts = [path: file_path, type: type, schema: schema_module, fragments: fragments]

    query = Document.new(contents, query_opts)

    cond do
      ignore? ->
        Macro.escape(query)

      runtime_validation? ->
        # Validate on runtime
        validate_on_runtime(contents, query_opts, warn_location)

      true ->
        fragments_evaluated = Enum.map(fragments, fn f -> expand_fragment!(f, caller) end)
        query = Document.add_fragments(query, fragments_evaluated)

        do_validate(query, warn_location)

        Macro.escape(query)
    end
  end

  @doc """
  Creates GraphQL documents with dynamic content and validation.

  Supports both static and dynamic queries with compile-time validation.
  Can expand module attributes and function calls when `evaluate: true` is set.

  ## Options

    * `:type` - Document type (:query, :schema, :fragment) (default: :query)
    * `:ignore` - Skip validation (default: false)
    * `:runtime` - Validate at runtime instead of compile-time (default: false)
    * `:evaluate` - Try to expand function calls at compile time (default: false)
    * `:schema` - Schema module for validation (default: module schema if set)
    * `:fragments` - List of fragments to include (default: [])

  ## Examples

      # Static query with module attribute
      @fields "id name email"
      query = gql "query { user { \#{@fields} } }"

      # Dynamic query with fragments
      query = gql [fragments: [@user_fragment]], "query { user { ...UserFragment } }"

      # Runtime validation for fully dynamic content
      def build_query(field_list) do
        gql [runtime: true], "query { user { \#{field_list} } }"
      end

      # Schema validation
      query = gql [schema: MyApp.Schema], "query { user { id name } }"

  """
  defmacro gql(opts \\ [], ast)

  defmacro gql(opts, content) when is_binary(content) do
    caller = __CALLER__
    file = caller.file
    warn_location = warn_location([], caller)

    GraphqlQuery.MacroOptions.validate!(opts)

    ignore? = get_option(opts, :ignore, false, caller)
    runtime_validation? = get_option(opts, :runtime, false, caller)
    schema_module = get_schema_module(opts, caller)
    fragments = get_option(opts, :fragments, [], caller)

    type = get_option(opts, :type, :query, caller)

    query = Document.new(content, path: file, type: type, schema: schema_module)

    cond do
      ignore? ->
        Macro.escape(query)

      runtime_validation? ->
        # Validate on runtime
        query_opts = [path: file, type: type, schema: schema_module, fragments: fragments]

        validate_on_runtime(content, query_opts, warn_location)

      Enum.empty?(fragments) ->
        IO.warn(
          """
          [GraphqlQuery] GraphQL query is static.

          Using the ~GQL sigil for static queries is recommended.

          To disable this warning, use the [ignore: true] option.
          """,
          warn_location
        )

        do_validate(query, warn_location)

        Macro.escape(query)

      true ->
        fragments_evaluated = Enum.map(fragments, fn f -> expand_fragment!(f, caller) end)
        query = Document.add_fragments(query, fragments_evaluated)

        do_validate(query, warn_location)

        Macro.escape(query)
    end
  end

  defmacro gql(opts, {:<<>>, meta, parts} = original) do
    # String with dynamic parts
    do_gql(original, parts, __CALLER__, meta, opts)
  end

  defmacro gql(opts, {_, meta, _} = ast) do
    # Method or module attribute call
    do_gql(ast, [ast], __CALLER__, meta, opts)
  end

  defp do_gql(original, parts, caller, meta, opts) do
    file = caller.file

    GraphqlQuery.MacroOptions.validate!(opts)

    warn_location = warn_location(meta, caller, -4)
    evaluate? = get_option(opts, :evaluate, false, caller)
    ignore? = get_option(opts, :ignore, false, caller)
    runtime_validation? = get_option(opts, :runtime, false, caller)

    schema_module = get_schema_module(opts, caller)

    type = get_option(opts, :type, :query, caller)

    fragments = get_option(opts, :fragments, [], caller)

    {static_parts, dynamic_parts} =
      Enum.map_reduce(parts, [], fn
        part, acc when is_binary(part) ->
          # Static part, no need to expand
          {part, acc}

        ast, acc ->
          case expand_until_string(ast, caller, evaluate?) do
            {:ok, value} ->
              # Successfully expanded to a string
              {value, acc}

            _ ->
              # We can't expand it :(

              {ast, acc ++ [ast]}
          end
      end)

    has_dynamic_parts? = dynamic_parts != []

    original_query =
      quote do
        Document.new(unquote(original),
          path: unquote(file),
          type: unquote(type),
          schema: unquote(schema_module),
          fragments: unquote(fragments)
        )
      end

    cond do
      ignore? ->
        original_query

      runtime_validation? ->
        # Validate on runtime
        query_opts = [path: file, type: type, schema: schema_module, fragments: fragments]

        validate_on_runtime(original, query_opts, warn_location)

      not has_dynamic_parts? ->
        # Compile validation

        compile_time_str = Enum.join(static_parts)

        query =
          Document.new(compile_time_str,
            path: file,
            type: type,
            schema: schema_module,
            fragments: fragments
          )

        do_validate(query, warn_location)

        Macro.escape(query)

      true ->
        # We have dynamic parts, no runtime validation and we don't ignore it, so print a warning

        Enum.each(dynamic_parts, fn expr ->
          IO.warn(error_msg(expr, evaluate?), warn_location(expr, caller))
        end)

        original_query
    end
  end

  @doc """
  GraphQL sigil for static queries with compile-time validation.

  Validates GraphQL queries, mutations, schemas, and fragments at compile time,
  providing immediate feedback on syntax errors, unused variables, and schema violations.
  Best suited for static GraphQL content without dynamic interpolation.

  ## Modifiers

  The sigil supports several modifiers that can be combined:

    * `i` - Ignore validation warnings
    * `r` - Validate at runtime instead of compile-time
    * `s` - Parse as schema document
    * `q` - Parse as query document (default)
    * `f` - Parse as fragment document

  ## Examples

  ### Basic Query

      import GraphqlQuery

      ~GQL\"\"\"
      query GetUser($id: ID!) {
        user(id: $id) {
          id
          name
          email
        }
      }
      \"\"\"

  ### Schema Definition

      ~GQL\"\"\"
      type User {
        id: ID!
        name: String!
        email: String!
      }

      type Query {
        user(id: ID!): User
      }
      \"\"\"s

  ### Fragment Definition

      ~GQL\"\"\"
      fragment UserData on User {
        id
        name
        email
      }
      \"\"\"f

  ### Ignoring Validation Warnings

      # For queries with intentional unused variables
      ~GQL\"\"\"
      query GetUser($id: ID!, $unused: String) {
        user(id: $id) { name }
      }
      \"\"\"i

  ### Runtime Validation

      # When fragments will be added later
      ~GQL\"\"\"
      query GetUser($id: ID!) {
        user(id: $id) {
          ...UserFragment
        }
      }
      \"\"\"r |> GraphqlQuery.Document.add_fragment(user_fragment)

  ## Integration with Mix Format

  The sigil integrates with `mix format` when the formatter plugin is configured:

      # .formatter.exs
      [
        plugins: [GraphqlQuery.Formatter]
      ]
  """
  defmacro sigil_GQL(data, opts) do
    quote do
      sigil_GQL(unquote(data), unquote(opts), [])
    end
  end

  # credo:disable-for-next-line
  defmacro sigil_GQL({:<<>>, meta, [query_string]}, opts, extra_opts) do
    # Validate at compile time
    caller = __CALLER__
    file = caller.file
    warn_location = warn_location(meta, caller)

    ignore? =
      if ?i in opts do
        true
      else
        get_option(extra_opts, :ignore, false, caller)
      end

    runtime? =
      if ?r in opts do
        true
      else
        get_option(extra_opts, :runtime, false, caller)
      end

    type =
      cond do
        ?s in opts ->
          :schema

        ?q in opts ->
          :query

        ?f in opts ->
          :fragment

        true ->
          get_option(extra_opts, :type, :query, caller)
      end

    schema_module =
      if module = get_option(extra_opts, :schema, nil, caller) do
        ensure_module_loaded!(module)
      else
        nil
      end

    fragments = get_option(extra_opts, :fragments, [], caller)

    query_opts = [path: file, type: type, schema: schema_module, fragments: fragments]

    query =
      Document.new(query_string, query_opts)

    cond do
      ignore? ->
        # If the ignore option is set, we skip validation
        :ok

      runtime? ->
        # We want to validate on runtime anyway, maybe we'll add fragments later
        validate_on_runtime(query_string, query_opts, warn_location)

      Parser.has_dynamic_parts?(to_string(query)) ->
        msg = """
        [GraphqlQuery] GraphQL query contains dynamic parts.
        │
        │ Use the "gql" macro instead to expand them and validate the query.
        │
        │ To disable this warning, use the `i` modifier: ~g"{}"#{opts}i
        """

        IO.warn(msg, warn_location)

      true ->
        case Validator.validate(query) do
          :ok ->
            :ok

          {:error, errors} ->
            prefix =
              "Validation errors, if you want to ignore them use the i modifier: ~G\"{}\"#{opts}i\n"

            print_warnings(errors, warn_location, prefix)
        end
    end

    Macro.escape(query)
  end

  defp warn_location(meta, caller, shift \\ 0)

  defp warn_location({_, meta, _}, caller, shift), do: warn_location(meta, caller, shift)

  defp warn_location(meta, %{line: line, file: file, function: function, module: module}, shift) do
    line = if meta[:line], do: meta[:line], else: line
    column = if column = meta[:column], do: column + shift
    [line: line, function: function, module: module, file: file, column: column]
  end

  defp expand_until_string(ast, caller, evaluate?) do
    ast
    |> Macro.prewalker()
    |> Enum.reduce_while(:error, fn
      string, acc when is_binary(string) ->
        # We went too far
        {:halt, acc}

      {:@, _, [{name, _, _}]}, acc ->
        case get_module_attribute(caller.module, name) do
          binary when is_binary(binary) ->
            {:halt, {:ok, binary}}

          %GraphqlQuery.Fragment{} = fragment ->
            {:halt, {:ok, fragment}}

          %GraphqlQuery.Document{} = document ->
            {:halt, {:ok, to_string(document)}}

          :undefined ->
            {:halt, {:error, :module_attribute}}

          _ ->
            {:cont, acc}
        end

      expr, acc ->
        case Macro.expand(expr, caller) do
          string when is_binary(string) ->
            {:halt, {:ok, string}}

          ast ->
            maybe_evaluate_ast(ast, caller, acc, evaluate?)
        end
    end)
  end

  # credo:disable-for-next-line
  defp expand_fragment!(ast, caller) do
    ast
    |> Macro.prewalker()
    |> Enum.reduce_while(:error, fn
      string, acc when is_binary(string) ->
        # We went too far
        {:halt, acc}

      {:@, _, [{name, _, _}]}, acc ->
        case get_module_attribute(caller.module, name) do
          %GraphqlQuery.Fragment{} = fragment ->
            {:halt, {:ok, fragment}}

          %GraphqlQuery.Document{} ->
            {:halt, {:error, :document}}

          :undefined ->
            {:halt, {:error, :module_attribute}}

          _ ->
            {:cont, acc}
        end

      expr, acc ->
        case Macro.expand(expr, caller) do
          {:%{}, [], q} = struct_ast ->
            case q[:__struct__] do
              GraphqlQuery.Document ->
                {:halt, {:error, :document}}

              GraphqlQuery.Fragment ->
                {fragment, _} = Code.eval_quoted(struct_ast)
                {:halt, {:ok, fragment}}

              _ ->
                {:cont, acc}
            end

          ast ->
            # credo:disable-for-next-line
            case evaluate_ast(ast, caller) do
              {:ok, %GraphqlQuery.Fragment{} = fragment} ->
                {:halt, {:ok, fragment}}

              {:ok, %GraphqlQuery.Document{}} ->
                {:halt, {:error, :document}}

              _ ->
                {:cont, acc}
            end
        end
    end)
    |> case do
      {:ok, fragment} ->
        fragment

      {:error, error} ->
        msg = error_msg_invalid_fragment(ast, error)
        IO.warn(msg, warn_location(ast, caller))
        nil

      :error ->
        msg = error_msg_invalid_fragment(ast, nil)
        IO.warn(msg, warn_location(ast, caller))
        nil
    end
  end

  defp maybe_evaluate_ast(_ast, _caller, acc, false) do
    {:cont, acc}
  end

  defp maybe_evaluate_ast(ast, caller, acc, true) do
    case evaluate_ast(ast, caller) do
      {:ok, value} when is_binary(value) ->
        {:halt, {:ok, value}}

      {:ok, %GraphqlQuery.Document{} = query} ->
        {:halt, {:ok, to_string(query)}}

      {:ok, %GraphqlQuery.Fragment{} = fragment} ->
        {:halt, {:ok, to_string(fragment)}}

      _ ->
        {:cont, acc}
    end
  end

  # Function calls
  defp evaluate_ast({{:., _, _}, _, _} = ast, caller) do
    ensure_modules_loaded(ast)
    {value, _binding} = Code.eval_quoted(ast, [], caller)
    {:ok, value}
  rescue
    _ ->
      :error
  end

  defp evaluate_ast({:@, _, _} = ast, caller) do
    {value, _binding} = Code.eval_quoted(ast, [], caller)
    {:ok, value}
  rescue
    _ ->
      :error
  end

  defp evaluate_ast(_ast, _caller), do: :ignore

  defp ensure_modules_loaded({:., _meta, [module | _]}) do
    ensure_module_loaded!(module)
  end

  defp ensure_modules_loaded({{:., _, _} = call_ast, _, asts}) do
    ensure_modules_loaded(call_ast)
    Enum.each(asts, &ensure_module_loaded!/1)
  end

  defp ensure_modules_loaded({_, _meta, asts}) when is_list(asts) do
    Enum.each(asts, &ensure_modules_loaded/1)
  end

  defp ensure_module_loaded!(nil), do: nil

  defp ensure_module_loaded!({:__aliases__, _meta, [module | _] = parts}) when is_atom(module) do
    parts |> Module.concat() |> ensure_module_loaded!()
  end

  defp ensure_module_loaded!(module) when is_atom(module) do
    Code.ensure_compiled!(module)
    Code.ensure_loaded!(module)
    module
  end

  defp ensure_module_loaded!(other), do: other

  defp validate_on_runtime(document, query_opts, warn_location) do
    quote do
      require Logger
      calculated_query = unquote(document)
      file_path = unquote(warn_location)[:file]

      query = Document.new(calculated_query, unquote(query_opts))

      case Validator.validate(query) do
        :ok ->
          :ok

        {:error, errors} ->
          Enum.each(errors, fn error ->
            error = GraphqlQuery.Parser.format_error(error, unquote(warn_location), :runtime)

            Logger.warning(error.message, error.location)
          end)
      end

      query
    end
  end

  defp do_validate(document, warn_location) do
    case Validator.validate(document) do
      :ok ->
        document

      {:error, errors} ->
        print_warnings(errors, warn_location, "Validation error:")

        document
    end
  end

  defp print_warnings(errors, warn_location, prefix) do
    Enum.each(errors, fn error ->
      error = Parser.format_error(error, warn_location, prefix)

      IO.warn(error.message, error.location)
    end)
  end

  defp error_msg_invalid_fragment(ast, :document) do
    # We tried to evaluate the query at compile time, but it failed

    """
    [GraphqlQuery] Fragment in #{Macro.to_string(ast)} evaluated as %GraphqlQuery.Document{}

    In the fragment's definition use the option `type: :fragment`
    or the `f` modifier in the sigil `~GQL""f` to define a fragment.

    To ignore this warning, use the `ignore: true` option.
    """
  end

  defp error_msg_invalid_fragment(ast, :module_attribute) do
    # We tried to evaluate a @module_attribute at compile time, but it failed

    ast_string = Macro.to_string(ast)

    """
    [GraphqlQuery] Tried to evaluate the module attribute #{ast_string} at compile time and failed.

    This happens when you reference a non existing module attribute or from other module attribute,
    that's not possible in Elixir macros.

    Move this call to a method, or the module attribute #{ast_string} to another module.

    To ignore this warning, use the `ignore: true` option.
    """
  end

  defp error_msg_invalid_fragment(ast, _) do
    # We tried to evaluate the query at compile time, but it failed

    """
    [GraphqlQuery] Could not expand to a valid %GraphqlQuery.Fragment{} struct the part #{Macro.to_string(ast)} at compile time.

    To validate in runtime, use the `runtime: true` option.
    To ignore this warning, use the `ignore: true` option.
    """
  end

  defp error_msg(ast, true) do
    # We tried to evaluate the query at compile time, but it failed

    """
    [GraphqlQuery] Could not expand and evaluate the part #{Macro.to_string(ast)} at compile time.

    To validate in runtime, use the `runtime: true` option.
    To ignore this warning, use the `ignore: true` option.
    """
  end

  defp error_msg(ast, false) do
    # We tried to expand, but not evaluate

    """
    [GraphqlQuery] Could not expand the part #{Macro.to_string(ast)} at compile time.

    To try to evaluate calls at compile time, use the `evaluate: true` option.
    To validate in runtime, use the `runtime: true` option.
    To ignore this warning, use the `ignore: true` option.
    """
  end

  defp get_schema_module(opts, caller) do
    case get_option(opts, :schema, nil, caller) do
      nil ->
        nil

      :not_set ->
        # If schema is not set, we try to get it from the module attributes
        get_module_attribute(caller.module, :__graphql_query__schema, nil)
        |> ensure_module_loaded!()

      module when is_atom(module) ->
        ensure_module_loaded!(module)

      {:__aliases__, _meta, _mod_parts} = module_alias ->
        ensure_module_loaded!(module_alias)

      _ ->
        nil
    end
  end

  defp get_option(opts, key, default, caller) do
    module_attribute_key = :"__graphql_query__#{key}"

    case Keyword.get(opts, key) do
      nil ->
        get_module_attribute(caller.module, module_attribute_key, default)

      value ->
        value
    end

    # case get_in(opts, [Access.key(key)]) do
    #   nil ->
    #     get_module_attribute(caller.module, module_attribute_key, default)

    #   value ->
    #     value
    # end
  end

  defp get_module_attribute(module, key) do
    if Module.has_attribute?(module, key) do
      Module.get_attribute(module, key)
    else
      :undefined
    end
  end

  defp get_module_attribute(nil, _key, default), do: default

  defp get_module_attribute(module, key, default) do
    case Module.get_attribute(module, key, default) do
      nil -> default
      value -> value
    end
  end
end
