defmodule GraphqlQuery.MutationInfo do
  @moduledoc """
  Represents information about a GraphQL mutation operation.

  This struct captures details about GraphQL mutations, including the
  optional operation name and a list of fragments used within the mutation.
  """

  defstruct [:name, :fragments, :location]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          fragments: [String.t()],
          location: GraphqlQuery.Location.t() | nil
        }
end
