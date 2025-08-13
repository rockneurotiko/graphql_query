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

  defmacro gql(opt \\ [], ast)

  defmacro gql(opts, ast) when is_binary(ast) do
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
    end

    do_validate(ast, file, warn_location)

    ast
  end

  defmacro gql(opts, {:<<>>, meta, parts} = original) do
    # String with dynamic parts

    caller = __CALLER__
    file = caller.file
    warn_location = warn_location(meta, caller)
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

          case Validator.validate(calculated_query, unquote(file)) do
            :ok ->
              :ok

            {:error, errors} ->
              error_strings = Enum.join(errors, "\n")

              Logger.warning(
                "[GraphqlQuery] GraphQL runtime validation errors:\n#{error_strings}",
                unquote(warn_location)
              )
          end

          calculated_query
        end

      has_dynamic_parts? and ignore? ->
        # We have dynamic parts, but we ignore it
        original

      true ->
        # We have dynamic parts, no runtime validation and we don't ignore it, so print a warning

        Enum.each(dynamic_parts, fn expr ->
          evaluate_msg =
            if not evaluate?,
              do:
                "You can try to evaluate calls at compile time with the [evaluate: true] option."

          msg_parts = [
            "Could not expand #{Macro.to_string(expr)} at compile time.",
            evaluate_msg,
            "To validate in runtime, use the [runtime: true] option.",
            "To disable this warning, use the [ignore: true] option."
          ]

          msg = msg_parts |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")

          IO.warn(msg, warn_location)
        end)

        original
    end
  end

  defmacro gql(opts, {_, meta, _} = ast) do
    # Method or module attribute call

    caller = __CALLER__
    file = caller.file
    evaluate? = get_option(opts, :evaluate, false, caller)
    runtime_validation? = get_option(opts, :runtime, false, caller)
    ignore? = get_option(opts, :ignore, false, caller)

    warn_location = warn_location(meta, caller)

    {compile_time_str, has_runtime?} =
      case expand_until_string(ast, caller, evaluate?) |> dbg() do
        {:ok, value} ->
          {value, false}

        :error ->
          if not ignore? and not runtime_validation? do
            IO.warn(
              """
              Could not expand #{Macro.to_string(ast)} at compile time.

              To validate in runtime, use the `runtime: true` option.

              To try to evaluate calls at compile time, use the `evaluate: true` option.

              To disable this warning, use the `ignore: true` option.
              """,
              warn_location
            )
          end

          {ast, true}
      end

    cond do
      has_runtime? and runtime_validation? ->
        # Validate on runtime

        quote do
          case Validator.validate(unquote(ast), unquote(file)) do
            :ok ->
              :ok

            {:error, errors} ->
              error_strings = Enum.join(errors, "\n")

              IO.warn(
                "[GraphqlQuery] GraphQL runtime validation errors:\n#{error_strings}",
                unquote(warn_location)
              )
          end

          unquote(ast)
        end

      has_runtime? ->
        ast

      true ->
        do_validate(compile_time_str, file, warn_location)

        ast
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

        Use the "gql" macro instead to expand them and validate the query.

        To disable this warning, use the `i` modifier: ~g"{}"#{opts}i
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
            error_strings = Enum.join(errors, "\n")

            msg = """
            GraphQL validation errors.
            If you want to ignore the warning use the i modifier: ~G"{}"#{opts}i

            #{error_strings}
            """

            IO.warn(msg, warn_location)
        end
    end

    # Always return the query string
    original
  end

  defp warn_location(meta, %{line: line, file: file, function: function, module: module}) do
    column = if column = meta[:column], do: column + 2
    [line: line, function: function, module: module, file: file, column: column]
  end

  defp expand_until_string(ast, caller, evaluate?) do
    ast
    |> Macro.prewalker()
    |> Enum.reduce_while(:error, fn expr, acc ->
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
    {value, _binding} = Code.eval_quoted(ast, [], caller)
    {:ok, value}
  rescue
    _ ->
      :error
  end

  defp evaluate_ast(_ast, _caller), do: :ignore

  defp do_validate(string, file, warn_location) do
    case Validator.validate(string, file) do
      :ok ->
        string

      {:error, errors} ->
        error_strings = Enum.join(errors, "\n")

        IO.warn("GraphQL validation errors:\n#{error_strings}", warn_location)

        string
    end
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
