defmodule GraphqlQuery.Logger do
  @moduledoc """
  Logger helper to differentiate between compile time and runtime warnings.

  In compile time it will use `IO.warn/2`, in runtime it will use `Logger.warning/2`.
  """

  require Logger

  defmacro warning(message, location) do
    case __CALLER__.module do
      GraphqlQuery ->
        # Compile time call
        quote do
          IO.warn(unquote(message), unquote(location))
        end

      _ ->
        # Runtime call - message is already formatted by the caller
        quote do
          require Logger
          Logger.warning(unquote(message), unquote(location))
        end
    end
  end
end
