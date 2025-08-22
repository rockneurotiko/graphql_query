defmodule GraphqlQuery.QueryInfo do
  @moduledoc """
  Represents information about a GraphQL query operation.

  This struct captures details about GraphQL queries, including the
  optional operation name and a list of fragments used within the query.
  """

  defstruct [:name, :fragments, :location]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          fragments: [String.t()],
          location: GraphqlQuery.Location.t() | nil
        }
end
