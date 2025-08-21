defmodule GraphqlQuery.FragmentInfo do
  @moduledoc """
  Represents information about a GraphQL fragment with its dependencies.

  This struct captures essential details about GraphQL fragments, including
  the fragment name and a list of other fragments it depends on.
  """

  defstruct [:name, :fragments]

  @type t :: %__MODULE__{
          name: String.t(),
          fragments: [String.t()]
        }
end
