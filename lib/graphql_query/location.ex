defmodule GraphqlQuery.Location do
  @moduledoc """
  Represents a location in a GraphQL validation error.
  """

  defstruct [:line, :column, indentation: 0]

  @type t :: %__MODULE__{
          line: non_neg_integer(),
          column: non_neg_integer(),
          indentation: non_neg_integer()
        }

  def new(line, column, indentation \\ 0) do
    %__MODULE__{line: line, column: column, indentation: indentation}
  end
end
