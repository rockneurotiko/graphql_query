defmodule GraphqlQuery do
  @external_resource "README.md"

  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  alias __MODULE__.{Parser, Validator}

  defmacro __using__(opts) do
    runtime? = Keyword.get(opts, :runtime, false)
    evaluate? = Keyword.get(opts, :evaluate, false)
    ignore? = Keyword.get(opts, :ignore, false)

    quote do
      import unquote(__MODULE__)

      Module.put_attribute(__MODULE__, :__graphql_query__runtime, unquote(runtime?))
      Module.put_attribute(__MODULE__, :__graphql_query__ignore, unquote(ignore?))
      Module.put_attribute(__MODULE__, :__graphql_query__evaluate, unquote(evaluate?))
    end
  end

  defmacro gql_from_file(file_path, opts \\ []) do
    Module.put_attribute(__CALLER__.module, :external_resource, file_path)

    ignore? = get_option(opts, :ignore, false, __CALLER__)

    contents = File.read!(file_path)

    location_info = [file: file_path]

    if not ignore? do
      do_validate(contents, file_path, location_info)
    end

    contents
  end

  defmacro gql(opts \\ [], ast)

  defmacro gql(opts, query) when is_binary(query) do
    caller = __CALLER__
    file = caller.file
    warn_location = warn_location([], caller)

    ignore? = get_option(opts, :ignore, false, caller)

    if not ignore? do
      IO.warn(
        """
        [GraphqlQuery] GraphQL query is static.

        Using the ~GQL sigil for static queries is recommended.

        To disable this warning, use the [ignore: true] option.
        """,
        warn_location
      )

      do_validate(query, file, warn_location)
    end

    query
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
    warn_location = warn_location(meta, caller, -4)
    evaluate? = get_option(opts, :evaluate, false, caller)
    ignore? = get_option(opts, :ignore, false, caller)
    runtime_validation? = get_option(opts, :runtime, false, caller)

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

            :error ->
              # We can't expand it :(

              {ast, acc ++ [ast]}
          end
      end)

    has_dynamic_parts? = dynamic_parts != []

    cond do
      not has_dynamic_parts? ->
        compile_time_str = Enum.join(static_parts)

        do_validate(compile_time_str, file, warn_location)

        # Return the original value, not the calculated
        original

      has_dynamic_parts? and runtime_validation? ->
        # Validate on runtime

        quote do
          require Logger
          calculated_query = unquote(original)
          file_path = unquote(warn_location)[:file]

          case Validator.validate(calculated_query, unquote(file)) do
            :ok ->
              :ok

            {:error, errors} ->
              Enum.each(errors, fn error ->
                error =
                  GraphqlQuery.Parser.format_error(
                    error,
                    unquote(warn_location),
                    fn loc ->
                      "Runtime Validation error @ #{file_path}:#{loc[:line]}:#{loc[:column]} ->"
                    end
                  )

                Logger.warning(error.message, error.location)
              end)
          end

          calculated_query
        end

      has_dynamic_parts? and ignore? ->
        # We have dynamic parts, but we ignore it
        original

      true ->
        # We have dynamic parts, no runtime validation and we don't ignore it, so print a warning

        Enum.each(dynamic_parts, fn expr ->
          IO.warn(error_msg(expr, evaluate?), warn_location(expr, caller))
        end)

        original
    end
  end

  @doc """
  GraphQL sigil that validates static queries at compile time and prints warnings for any errors.

  Usage:
      import GraphqlQuery

      ~GQL\"\"\"
      query GetUser($id: ID!) {
        user(id: $id) {
          name
          email
        }
      }
      \"\"\"
  """
  defmacro sigil_GQL({:<<>>, meta, [query]} = original, opts) do
    # Validate at compile time
    caller = __CALLER__
    file = caller.file
    warn_location = warn_location(meta, caller)

    ignore? = get_option(opts, ?i, false, caller, :__graphql_query__ignore)

    cond do
      Parser.has_dynamic_parts?(query) and not ignore? ->
        msg = """
        [GraphqlQuery] GraphQL query contains dynamic parts.
        │
        │ Use the "gql" macro instead to expand them and validate the query.
        │
        │ To disable this warning, use the `i` modifier: ~g"{}"#{opts}i
        """

        IO.warn(msg, warn_location)

      ignore? ->
        # If the ignore option is set, we skip validation
        :ok

      true ->
        case Validator.validate(query, file) do
          :ok ->
            :ok

          {:error, errors} ->
            prefix =
              "Validation errors, if you want to ignore them use the i modifier: ~G\"{}\"#{opts}i\n"

            print_warnings(errors, warn_location, prefix)
        end
    end

    # Always return the query string
    original
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

      expr, acc ->
        case Macro.expand(expr, caller) do
          string when is_binary(string) ->
            {:halt, {:ok, string}}

          ast ->
            if evaluate? do
              case evaluate_ast(ast, caller) do
                {:ok, value} when is_binary(value) ->
                  {:halt, {:ok, value}}

                _ ->
                  {:cont, acc}
              end
            else
              {:cont, acc}
            end
        end
    end)
  end

  # Function calls
  defp evaluate_ast({{:., _, _}, _, _} = ast, caller) do
    ensure_modules_loaded(ast)
    {value, _binding} = Code.eval_quoted(ast, [], caller)
    {:ok, value}
  rescue
    _e ->
      :error
  end

  defp evaluate_ast(_ast, _caller), do: :ignore

  defp ensure_modules_loaded({:., _meta, [module | _]}) do
    ensure_module_loaded(module)
  end

  defp ensure_modules_loaded({{:., _, _} = call_ast, _, asts}) do
    ensure_modules_loaded(call_ast)
    Enum.each(asts, &ensure_module_loaded/1)
  end

  defp ensure_modules_loaded({_, _meta, asts}) when is_list(asts) do
    Enum.each(asts, &ensure_modules_loaded/1)
  end

  defp ensure_module_loaded({:__aliases__, _meta, [module | _] = parts}) when is_atom(module) do
    parts |> Module.concat() |> ensure_module_loaded()
  end

  defp ensure_module_loaded(module) when is_atom(module) do
    Code.ensure_compiled!(module)
    Code.ensure_loaded!(module)
  end

  defp do_validate(string, file, warn_location) do
    case Validator.validate(string, file) do
      :ok ->
        string

      {:error, errors} ->
        print_warnings(errors, warn_location, "Validation error:")

        string
    end
  end

  defp print_warnings(errors, warn_location, prefix) do
    Enum.each(errors, fn error ->
      error = Parser.format_error(error, warn_location, prefix)

      IO.warn(error.message, error.location)
    end)
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

  defp get_option(opts, key, default, caller) do
    # Macro option
    case Keyword.get(opts, key) do
      nil ->
        module_attribute_key = :"__graphql_query__#{key}"
        Module.get_attribute(caller.module, module_attribute_key, default)

      value ->
        value
    end
  end

  defp get_option(opts, key, default, caller, module_attribute_key) do
    # Sigil options
    if key in opts do
      true
    else
      Module.get_attribute(caller.module, module_attribute_key, default)
    end
  end
end
