defmodule GraphqlQuery.Location do
  @moduledoc """
  Represents a location in a GraphQL validation error.
  """

  defstruct [:line, :column]

  @type t :: %__MODULE__{
          line: non_neg_integer(),
          column: non_neg_integer()
        }
end
