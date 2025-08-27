defmodule GraphqlQuery do
  @external_resource "README.md"

  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)
             |> String.replace("](#", "](#module-")

  alias __MODULE__.{Parser, Document, Validator}

  require GraphqlQuery.Logger

  defguardp ast?(value) when is_tuple(value) and tuple_size(value) == 3

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
    caller = __CALLER__
    module = caller.module
    schema = opts[:schema]
    {:ok, opts} = validate_options!(opts, caller)
    opts = GraphqlQuery.MacroOptions.validate!(opts)

    if schema do
      loaded_schema = ensure_module_loaded!(schema, caller)
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

  @doc """
  Applies GraphQL macro options to all GraphQL macros within a block.

  This macro provides a convenient way to apply common options to multiple GraphQL
  macros (`~GQL`, `gql`, `gql_from_file`) within a do block, but it's recommended to
  apply it only for one.

  The most important use case is enabling the `~GQL` sigil to work with complex
  options like `:schema` and `:fragments`, which are not directly available through
  sigil modifiers.

  If the options can't be expanded on compile time, a warning is printed and
  the validation are applied at runtime instead.

  ## Options

    * `:type` - Document type (:query, :schema, :fragment) (default: :query)
    * `:ignore` - Skip validation (default: false)
    * `:runtime` - Validate at runtime instead of compile-time (default: false)
    * `:evaluate` - Try to expand function calls at compile time (default: false)
    * `:schema` - Schema module for validation (default: module schema if set)
    * `:fragments` - List of fragments to include (default: [])

  ## Option Precedence

  Options are merged with the following precedence (highest to lowest):

  1. Explicit options on individual macros (e.g., `gql [ignore: false], "..."`)
  2. Sigil modifiers (e.g., `~GQL"..."f` for fragment type)
  3. Options from `document_with_options`
  4. Module-level defaults from `use GraphqlQuery`

  ## Examples

  ### Basic Usage with Schema Validation

      document_with_options schema: MySchema do
        ~GQL\"\"\"
        query GetUser { user { ...UserFragment } }
        \"\"\"  # ✅ Schema validation applied
      end


  ### Using Fragments

      user_fragment = ~GQL\"\"\"
      fragment UserFields on User {
        id
        name
        email
      }
      \"\"\"f

      document_with_options fragments: [user_fragment] do
        ~GQL\"\"\"
        query GetUserWithFragment {
          user {
            ...UserFields
          }
        }
        \"\"\"
      end

  ### Schema Validation for Multiple Documents (but set it in `use GraphqlQuery, schema: Schema` is prefered)

      document_with_options schema: MyApp.Schema do
        @user_query ~GQL\"\"\"
        query GetUser($id: ID!) {
          user(id: $id) { id name }
        }
        \"\"\"

        @users_query ~GQL\"\"\"
        query GetUsers {
          users { id name }
        }
        \"\"\"
      end

  ### Fragment Management

      @user_fields ~GQL\"\"\"
      fragment UserFields on User {
        id name email
      }
      \"\"\"f

      document_with_options fragments: [@user_fields] do
        @get_user ~GQL\"\"\"
        query GetUser { user { ...UserFields } }
        \"\"\"

        @get_users ~GQL\"\"\"
        query GetUsers { users { ...UserFields } }
        \"\"\"
      end

  ## Integration Notes

  This macro works by walking the AST of the provided block and transforming
  all GraphqlQuery macro calls to include the specified options. It supports:

  - `~GQL` sigil (adds options as third parameter)
  - `gql/1` and `gql/2` macro calls
  - `gql_from_file/1` and `gql_from_file/2` macro calls

  The transformation happens at compile time, so there's no runtime overhead.
  """
  defmacro document_with_options(opts, do: block) do
    caller = __CALLER__

    warn_location = warn_location([], caller)

    opts =
      case validate_options!(opts, caller) do
        {:ok, opts} ->
          opts

        {:error, error, field} ->
          warning_options_error(error, field, warn_location)
          {:runtime, [opts]}

        {:ignore, opts} ->
          opts

        {:runtime, opts} ->
          opts
      end

    modified_block = Macro.prewalk(block, fn ast -> add_extra_opts_to_ast(ast, opts) end)

    quote do
      unquote(modified_block)
    end
  end

  defp warning_options_error({:invalid_fragments, errors}, _field, warn_location) do
    Enum.each(errors, fn {error, ast} ->
      msg_line = error_msg_invalid_fragment(ast, error)

      msg = expand_error_msg(msg_line)

      GraphqlQuery.Logger.warning(msg, warn_location)
    end)
  end

  defp warning_options_error(_error, field, warn_location) do
    msg_line =
      case field do
        :opts -> "[GraphqlQuery] Can't extract options on compile time."
        _ -> "Can't extract the value for the option \"#{field}\" on compile time."
      end

    msg = expand_error_msg(msg_line)

    GraphqlQuery.Logger.warning(msg, warn_location)
  end

  defp expand_error_msg(error_line) do
    """
    [GraphqlQuery] #{error_line}

    Falling back to runtime validation.

    If you want to learn more about what is allowed in Elixir Macros you can read
    the following documentation https://hexdocs.pm/graphql_query/macros.html
    """
  end

  defp global_ignore?(caller) do
    get_module_attribute(caller.module, :__graphql_query__ignore, false)
  end

  defp global_runtime?(caller) do
    get_module_attribute(caller.module, :__graphql_query__runtime, false)
  end

  defp add_extra_opts_to_ast(ast, extra_opts) do
    case ast do
      {:sigil_GQL, meta, [query, opts]} ->
        {:sigil_GQL, meta, [query, opts, extra_opts]}

      {:sigil_GQL, meta, [query, opts, current_extra_opts]} ->
        new_opts = merge_extra_opts(current_extra_opts, extra_opts)
        {:sigil_GQL, meta, [query, opts, new_opts]}

      {:gql, meta, [data]} ->
        {:gql, meta, [extra_opts, data]}

      {:gql, meta, [opts, data]} ->
        new_opts = merge_extra_opts(opts, extra_opts)
        {:gql, meta, [new_opts, data]}

      {:gql_from_file, meta, [data]} ->
        {:gql_from_file, meta, [data, extra_opts]}

      {:gql_from_file, meta, [data, opts]} ->
        new_opts = merge_extra_opts(opts, extra_opts)
        {:gql_from_file, meta, [data, new_opts]}

      other ->
        other
    end
  end

  defp merge_extra_opts({:runtime, opts}, {:runtime, extra_opts}) do
    opts = List.wrap(opts)
    extra_opts = List.wrap(extra_opts)
    {:runtime, opts ++ extra_opts}
  end

  defp merge_extra_opts({:runtime, opts}, extra_opts) do
    opts = List.wrap(opts)
    extra_opts = List.wrap(extra_opts)
    {:runtime, extra_opts ++ List.wrap(opts)}
  end

  defp merge_extra_opts(opts, {:runtime, extra_opts}) do
    opts = List.wrap(opts)
    extra_opts = List.wrap(extra_opts)
    {:runtime, opts ++ extra_opts}
  end

  defp merge_extra_opts(opts, extra_opts) do
    Keyword.merge(extra_opts, opts)
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

  defmacro gql_from_file(file_path, opts \\ [])

  defmacro gql_from_file(file_path, {:runtime, opts}) do
    Module.put_attribute(__CALLER__.module, :external_resource, file_path)
    caller = __CALLER__
    warn_location = [file: file_path]
    module_opts = get_module_opts(caller)

    contents = File.read!(file_path)

    validate_on_runtime(contents, opts, module_opts, warn_location)
  end

  defmacro gql_from_file(file_path, opts) do
    caller = __CALLER__
    warn_location = [file: file_path]

    case validate_options!(opts, caller) do
      {:ok, opts} ->
        do_gql_from_file(file_path, opts, caller)

      {:error, error, field} ->
        warning_options_error(error, field, warn_location)
        opts = {:runtime, [opts]}
        {:gql_from_file, [], [file_path, opts]}

      {:ignore, opts} ->
        {:gql_from_file, [], [file_path, opts]}

      {:runtime, opts} ->
        {:gql_from_file, [], [file_path, opts]}
    end
  end

  def do_gql_from_file(file_path, opts, caller) do
    Module.put_attribute(caller.module, :external_resource, file_path)

    ignore? = get_option(opts, :ignore, false, caller)
    runtime_validation? = get_option(opts, :runtime, false, caller)
    type = get_option(opts, :type, :query, caller)
    schema_module = get_schema_module(opts, caller)
    fragments = get_option(opts, :fragments, [], caller)

    contents = File.read!(file_path)

    warn_location = [file: file_path]

    query_opts = [
      path: file_path,
      type: type,
      schema: schema_module,
      fragments: fragments,
      ignore?: ignore?,
      location: warn_location
    ]

    cond do
      ignore? ->
        contents
        |> Document.new(query_opts)
        |> Macro.escape()

      runtime_validation? ->
        module_opts = get_module_opts(caller)
        validate_on_runtime(contents, opts, module_opts, warn_location)

      true ->
        contents |> Document.new(query_opts) |> do_validate(warn_location) |> Macro.escape()
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

  defmacro gql({:runtime, opts}, content) do
    caller = __CALLER__
    warn_location = warn_location([], caller)
    module_opts = get_module_opts(caller)

    validate_on_runtime(content, opts, module_opts, warn_location)
  end

  defmacro gql(opts, content) when is_binary(content) do
    caller = __CALLER__
    warn_location = warn_location([], caller)

    case validate_options!(opts, caller) do
      {:ok, opts} ->
        ignore? = get_option(opts, :ignore, false, caller)
        runtime_validation? = get_option(opts, :runtime, false, caller)
        fragments = get_option(opts, :fragments, [], caller)

        cond do
          ignore? ->
            do_gql(content, [content], caller, [], opts)

          runtime_validation? ->
            # Validate on runtime
            module_opts = get_module_opts(caller)
            validate_on_runtime(content, opts, module_opts, warn_location)

          Enum.empty?(fragments) ->
            msg = """
            [GraphqlQuery] GraphQL query is static.

            Using the ~GQL sigil for static queries is recommended.

            To disable this warning, use the [ignore: true] option.
            """

            GraphqlQuery.Logger.warning(msg, warn_location)

            do_gql(content, [content], caller, [], opts)

          true ->
            do_gql(content, [content], caller, [], opts)
        end

      {:error, error, field} ->
        warning_options_error(error, field, warn_location)
        opts = {:runtime, [opts]}
        {:gql, [], [opts, content]}

      {:ignore, opts} ->
        {:gql, [], [opts, content]}

      {:runtime, opts} ->
        {:gql, [], [opts, content]}
    end
  end

  defmacro gql(opts, {:<<>>, meta, parts} = original) do
    # String with dynamic parts
    caller = __CALLER__

    case validate_options!(opts, caller) do
      {:ok, opts} ->
        do_gql(original, parts, caller, meta, opts)

      {:error, error, field} ->
        warning_options_error(error, field, warn_location(meta, caller))

        opts = {:runtime, [opts]}
        {:gql, [], [opts, original]}

      {:ignore, opts} ->
        {:gql, [], [opts, original]}

      {:runtime, opts} ->
        {:gql, [], [opts, original]}
    end
  end

  defmacro gql(opts, {_, meta, _} = ast) do
    # Method or module attribute call
    caller = __CALLER__

    case validate_options!(opts, caller) do
      {:ok, opts} ->
        do_gql(ast, [ast], caller, meta, opts)

      {:error, error, field} ->
        warning_options_error(error, field, warn_location(meta, caller))

        opts = {:runtime, [opts]}
        {:gql, [], [opts, ast]}

      {:ignore, opts} ->
        {:gql, [], [opts, ast]}

      {:runtime, opts} ->
        {:gql, [], [opts, ast]}
    end
  end

  defp do_gql(original, parts, caller, meta, opts) do
    file = caller.file

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

            {:error, error} ->
              # We can't expand it :(

              {ast, acc ++ [{ast, error}]}

            :error ->
              # We can't expand it :(

              {ast, acc ++ [{ast, :error}]}
          end
      end)

    has_dynamic_parts? = dynamic_parts != []

    query_opts = [
      path: file,
      type: type,
      schema: schema_module,
      fragments: fragments,
      ignore?: ignore?,
      location: warn_location
    ]

    module_opts = get_module_opts(caller)

    cond do
      ignore? ->
        quote do
          Document.new(unquote(original), unquote(query_opts))
        end

      runtime_validation? ->
        # Validate on runtime
        validate_on_runtime(original, opts, module_opts, warn_location)

      not has_dynamic_parts? ->
        # Compile validation

        compile_time_str = Enum.join(static_parts)

        compile_time_str
        |> Document.new(query_opts)
        |> do_validate(warn_location)
        |> Macro.escape()

      true ->
        # We have dynamic parts, no runtime validation and we don't ignore it, so print a warning

        Enum.each(dynamic_parts, fn {expr, error} ->
          msg = error_msg(expr, error, evaluate?)
          location = warn_location(expr, caller)

          GraphqlQuery.Logger.warning(msg, location)
        end)

        quote do
          Document.new(unquote(original), unquote(query_opts))
        end
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

  defmacro sigil_GQL({:<<>>, meta, [query_string]}, sigil_opts, {:runtime, extra_opts}) do
    caller = __CALLER__
    warn_location = warn_location(meta, caller)
    opts = opts_sigil_to_keyword(sigil_opts)
    module_opts = get_module_opts(caller)

    validate_on_runtime(query_string, opts, extra_opts, module_opts, warn_location)
  end

  # credo:disable-for-next-line
  defmacro sigil_GQL({:<<>>, meta, [query_string]}, sigil_opts, extra_opts) do
    # Validate at compile time
    caller = __CALLER__
    file = caller.file
    warn_location = warn_location(meta, caller)

    sigil_opts = opts_sigil_to_keyword(sigil_opts)
    module_opts = get_module_opts(caller)

    opts = extra_opts |> Keyword.merge(sigil_opts) |> compile_options(module_opts)

    ignore? = opts[:ignore]
    runtime? = opts[:runtime]
    type = opts[:type]
    schema_module = opts[:schema]
    fragments = opts[:fragments]

    query_opts = [
      path: file,
      type: type,
      schema: schema_module,
      fragments: fragments,
      ignore?: ignore?,
      location: warn_location
    ]

    cond do
      ignore? ->
        # If the ignore option is set, we skip validation
        query = Document.new(query_string, query_opts)
        Macro.escape(query)

      runtime? ->
        validate_on_runtime(query_string, opts, module_opts, warn_location)

      Parser.has_dynamic_parts?(query_string) ->
        msg = """
        [GraphqlQuery] GraphQL query contains dynamic parts.
        │
        │ Use the "gql" macro instead to expand them and validate the query.
        │
        │ To disable this warning, use the `i` modifier: ~g"{}"#{opts}i
        """

        GraphqlQuery.Logger.warning(msg, warn_location)

        query = Document.new(query_string, query_opts)
        Macro.escape(query)

      true ->
        query = Document.new(query_string, query_opts)

        query |> do_validate(warn_location, :sigil) |> Macro.escape()
    end
  end

  @options [
    {:ignore, false},
    {:runtime, false},
    {:evaluate, false},
    {:type, :query},
    {:schema, nil},
    {:fragments, []}
  ]

  def runtime_options(macro_opts, module_opts) do
    Keyword.new(@options, fn {opt, default} ->
      case Keyword.fetch(macro_opts, opt) do
        {:ok, v} -> {opt, v}
        :error -> {opt, Keyword.get(module_opts, opt, default)}
      end
    end)
  end

  defp compile_options(macro_opts, module_opts) do
    Keyword.new(@options, fn {opt, default} ->
      case Keyword.fetch(macro_opts, opt) do
        {:ok, v} ->
          {opt, v}

        :error ->
          {opt, Keyword.get(module_opts, opt, default)}
      end
    end)
  end

  defp warn_location(meta, caller, shift \\ 0)

  defp warn_location({_, meta, _}, caller, shift), do: warn_location(meta, caller, shift)

  defp warn_location(meta, %{line: line, file: file, function: function, module: module}, shift) do
    indentation = meta[:indentation] || 0
    line = if meta[:line], do: meta[:line], else: line
    column = if column = meta[:column], do: column + shift

    [
      line: line,
      function: function,
      module: module,
      file: file,
      column: column,
      indentation: indentation
    ]
  end

  defp expand_until(ast, caller, evaluate?, until_f) do
    ast
    |> Macro.prewalker()
    |> Enum.reduce_while(:error, fn
      string, acc when is_binary(string) ->
        # We went too far
        {:halt, acc}

      expr, acc ->
        with {:ok, value} <- expand_and_evaluate(expr, caller, evaluate?),
             {:ok, new_value} <- until_f.(value) do
          {:halt, {:ok, new_value}}
        else
          {:error, :module_attribute} ->
            {:halt, {:error, :module_attribute}}

          {:halt, error} ->
            {:halt, error}

          _ ->
            {:cont, acc}
        end
    end)
  end

  defp expand_until_string(ast, caller, evaluate?) do
    expand_until(ast, caller, evaluate?, fn
      string when is_binary(string) -> {:ok, string}
      %GraphqlQuery.Fragment{} = fragment -> {:ok, to_string(fragment)}
      %GraphqlQuery.Document{} = document -> {:ok, to_string(document)}
      _ -> :error
    end)
  end

  defp expand_fragments(fragments, caller) when is_list(fragments) do
    Enum.reduce(fragments, {[], []}, fn fragment, {valid, invalid} ->
      case expand_fragment(fragment, caller) do
        {:ok, fragment} -> {valid ++ [fragment], invalid}
        {:error, error} -> {valid, invalid ++ [{error, fragment}]}
        :error -> {valid, invalid ++ [{:unknown, fragment}]}
      end
    end)
  end

  defp expand_fragment(%GraphqlQuery.Fragment{} = fragment, _caller) do
    {:ok, fragment}
  end

  defp expand_fragment(ast, caller) do
    expand_until(ast, caller, true, fn
      %GraphqlQuery.Fragment{} = fragment -> {:ok, fragment}
      %GraphqlQuery.Document{} -> {:halt, {:error, :document}}
      other -> {:halt, {:error, {:not_fragment, other}}}
    end)
  end

  defp expand_and_evaluate({:@, _, [{name, _, _}]}, caller, _evaluate?) do
    case get_module_attribute(caller.module, name) do
      :undefined -> {:error, :module_attribute}
      value -> {:ok, value}
    end
  end

  defp expand_and_evaluate(ast, caller, evaluate?) when ast?(ast) do
    case Macro.expand(ast, caller) do
      ast when ast?(ast) ->
        maybe_evaluate_ast(ast, caller, evaluate?)

      value ->
        {:ok, value}
    end
  end

  defp expand_and_evaluate(value, _caller, _evaluate?), do: {:ok, value}

  defp maybe_evaluate_ast(ast, _caller, false) when ast?(ast), do: :error

  defp maybe_evaluate_ast(ast, caller, true) when ast?(ast) do
    evaluate_ast(ast, caller)
  end

  defp maybe_evaluate_ast(value, _caller, _evaluate?), do: {:ok, value}

  # Function calls
  defp evaluate_ast({{:., _, _}, _, _} = ast, caller) do
    ensure_modules_loaded(ast, caller)
    {value, _binding} = Code.eval_quoted(ast, [], caller)
    {:ok, value}
  rescue
    _e ->
      :error
  end

  defp evaluate_ast({:., _, _} = ast, caller) do
    ensure_modules_loaded(ast, caller)
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

  defp ensure_modules_loaded({{:., _, _} = call_ast, _, asts}, caller) do
    ensure_modules_loaded(call_ast, caller)
    Enum.each(asts, &ensure_module_loaded!(&1, caller))
  end

  defp ensure_modules_loaded({:., _meta, [module | _]}, caller) do
    ensure_module_loaded!(module, caller)
  end

  defp ensure_modules_loaded({_, _meta, asts}, caller) when is_list(asts) do
    Enum.each(asts, &ensure_modules_loaded(&1, caller))
  end

  defp ensure_module_loaded!(nil, _), do: nil

  defp ensure_module_loaded!({:__aliases__, _meta, [module | _]} = ast, caller)
       when is_atom(module) do
    ast |> Macro.expand(caller) |> ensure_module_loaded!()
  end

  defp ensure_module_loaded!(module, _caller) when is_atom(module) do
    ensure_module_loaded!(module)
  end

  defp ensure_module_loaded!(other, _caller), do: other

  defp ensure_module_loaded!(module) when is_atom(module) do
    Code.ensure_compiled!(module)
    Code.ensure_loaded!(module)
    module
  end

  defp ensure_module_loaded!(other), do: other

  defp opts_sigil_to_keyword(sigil_opts) do
    Enum.reduce(sigil_opts, [], fn
      ?i, acc -> Keyword.put(acc, :ignore, true)
      ?r, acc -> Keyword.put(acc, :runtime, true)
      ?s, acc -> Keyword.put(acc, :type, :schema)
      ?f, acc -> Keyword.put(acc, :type, :fragment)
      ?q, acc -> Keyword.put(acc, :type, :query)
      _, acc -> acc
    end)
  end

  defp get_module_opts(caller) do
    [
      runtime: get_module_attribute(caller.module, :__graphql_query__runtime, false),
      ignore: get_module_attribute(caller.module, :__graphql_query__ignore, false),
      evaluate: get_module_attribute(caller.module, :__graphql_query__evaluate, false),
      type: get_module_attribute(caller.module, :__graphql_query__type, :query),
      schema:
        get_module_attribute(caller.module, :__graphql_query__schema, nil)
        |> ensure_module_loaded!(caller),
      fragments: get_module_attribute(caller.module, :__graphql_query__fragments, [])
    ]
  end

  defp validate_on_runtime(document, opts, module_opts, warn_location) do
    validate_on_runtime(document, opts, [], module_opts, warn_location)
  end

  defp validate_on_runtime(document, opts, extra_opts, module_opts, warn_location) do
    quote do
      require GraphqlQuery.Logger
      calculated_query = unquote(document)
      file_path = unquote(warn_location)[:file]

      macro_opts = Keyword.merge(List.flatten(unquote(opts)), List.flatten(unquote(extra_opts)))
      opts = GraphqlQuery.runtime_options(macro_opts, unquote(module_opts))

      query_opts = [
        path: file_path,
        type: opts[:type],
        schema: opts[:schema],
        fragments: opts[:fragments],
        ignore?: opts[:ignore],
        location: unquote(warn_location)
      ]

      query = Document.new(calculated_query, query_opts)

      with {:ignore, ignore} when not ignore <- {:ignore, opts[:ignore]},
           :ok <- Validator.validate(query) do
        query
      else
        {:ignore, true} ->
          query

        {:error, errors} ->
          Enum.each(errors, fn error ->
            error = GraphqlQuery.Parser.format_error(error, unquote(warn_location), :runtime)

            GraphqlQuery.Logger.warning(error.message, error.location)
          end)

          query
      end
    end
  end

  defp do_validate(document, warn_location, source \\ :macro) do
    case Validator.validate(document) do
      :ok ->
        document

      {:error, errors} ->
        prefix =
          case source do
            :macro ->
              "Validation errors, if you want to ignore them use the [ignore: true] option.\n"

            :sigil ->
              "Validation errors, if you want to ignore them use the i modifier: ~G\"{}\"i\n"
          end

        print_warnings(errors, warn_location, prefix)

        document
    end
  end

  defp print_warnings(errors, warn_location, prefix) do
    Enum.each(errors, fn error ->
      error = Parser.format_error(error, warn_location, prefix)

      GraphqlQuery.Logger.warning(error.message, error.location)
    end)
  end

  defp error_msg_invalid_fragment(ast, :document) do
    # We tried to evaluate the query at compile time, but it failed
    "Fragment in #{Macro.to_string(ast)} evaluated as %GraphqlQuery.Document{}"
  end

  defp error_msg_invalid_fragment(ast, {:not_fragment, value}) do
    "Fragment in #{Macro.to_string(ast)} evaluated as #{inspect(value)} instead of %GraphqlQuery.Fragment{}"
  end

  defp error_msg_invalid_fragment(ast, :module_attribute) do
    # We tried to evaluate a @module_attribute at compile time, but it failed

    "Tried to evaluate the module attribute #{Macro.to_string(ast)} at compile time and failed."
  end

  defp error_msg_invalid_fragment(ast, _) do
    # We tried to evaluate the query at compile time, but it failed
    "Could not expand to a valid %GraphqlQuery.Fragment{} struct the part #{Macro.to_string(ast)} at compile time."
  end

  defp error_msg(ast, :module_attribute, _) do
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

  defp error_msg(ast, _error, true) do
    # We tried to evaluate the query at compile time, but it failed

    """
    [GraphqlQuery] Could not expand and evaluate the part #{Macro.to_string(ast)} at compile time.

    To validate in runtime, use the `runtime: true` option.
    To ignore this warning, use the `ignore: true` option.
    """
  end

  defp error_msg(ast, _error, false) do
    # We tried to expand, but not evaluate

    """
    [GraphqlQuery] Could not expand the part #{Macro.to_string(ast)} at compile time.

    To validate in runtime, use the `runtime: true` option.
    To try to evaluate calls at compile time, use the `evaluate: true` option.
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
        |> ensure_module_loaded!(caller)

      module when is_atom(module) ->
        ensure_module_loaded!(module, caller)

      {:__aliases__, _meta, _mod_parts} = module_alias ->
        ensure_module_loaded!(module_alias, caller)

      _ ->
        nil
    end
  end

  defp get_option(opts, key, default, caller) do
    module_attribute_key = :"__graphql_query__#{key}"

    if Keyword.has_key?(opts, key) do
      opts[key]
    else
      get_module_attribute(caller.module, module_attribute_key, default)
    end
  end

  defp validate_options!(opts, caller) do
    cond do
      global_ignore?(caller) ->
        opts = merge_extra_opts(opts, {:runtime, [ignore: true]})
        {:ignore, opts}

      global_runtime?(caller) ->
        opts = merge_extra_opts(opts, {:runtime, []})

        {:runtime, opts}

      true ->
        do_validate_options!(opts, caller)
    end
  end

  defp do_validate_options!({:@, _, [{name, _, _}]}, caller) do
    get_module_attribute(caller.module, name) |> do_validate_options!(caller)
  end

  defp do_validate_options!({_, _, _}, _) do
    {:error, :runtime, :opts}
  end

  defp do_validate_options!(nil, _), do: {:ok, []}

  defp do_validate_options!(options, caller) when is_list(options) do
    Enum.reduce_while(options, {:ok, []}, fn {k, v}, {:ok, acc} ->
      case validate_option_value(k, v, caller) do
        {:error, reason} ->
          {:halt, {:error, reason, k}}

        {:error, reason, data} ->
          {:halt, {:error, {reason, data}, k}}

        {:ok, valid_value} ->
          {:cont, {:ok, Keyword.put(acc, k, valid_value)}}
      end
    end)
    |> case do
      {:ok, opts} ->
        GraphqlQuery.MacroOptions.validate!(opts)
        {:ok, opts}

      other ->
        other
    end
  end

  defp do_validate_options!(_other, _caller), do: {:error, :unknown_options, :opts}

  @single_options [:ignore, :runtime, :evaluate, :type]

  defp validate_option_value(k, {_, _, _} = ast, caller) when k in @single_options do
    case expand_and_evaluate(ast, caller, true) do
      {:ok, module} -> {:ok, module}
      _ -> {:error, :runtime}
    end
  end

  defp validate_option_value(k, v, _caller) when k in @single_options do
    {:ok, v}
  end

  defp validate_option_value(:schema, {_, _, _} = ast, caller) do
    case expand_and_evaluate(ast, caller, true) do
      {:ok, schema} when is_atom(schema) ->
        ensure_module_loaded!(schema, caller)
        {:ok, schema}

      {:ok, value} ->
        {:ok, value}

      _ ->
        {:error, :runtime}
    end
  end

  defp validate_option_value(:schema, schema, caller) when is_atom(schema) do
    ensure_module_loaded!(schema, caller)
    {:ok, schema}
  end

  defp validate_option_value(:schema, schema, _caller), do: {:ok, schema}

  defp validate_option_value(:fragments, {_, _, _} = ast, caller) do
    case expand_and_evaluate(ast, caller, true) do
      {:ok, value} -> validate_option_value(:fragments, value, caller)
      :ignore -> {:error, :runtime}
      {:error, _} -> {:error, :runtime}
    end
  end

  defp validate_option_value(:fragments, frags, caller) when is_list(frags) do
    case expand_fragments(frags, caller) do
      {fragments, []} -> {:ok, fragments}
      {_fragments, invalid} -> {:error, :invalid_fragments, invalid}
    end
  end

  defp validate_option_value(:fragments, frags, _caller) do
    {:error, :invalid_fragments, [{:error, :not_a_list, frags}]}
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
