defmodule GraphqlQuery.ValidationError do
  @moduledoc """
  Represents a validation error in a GraphQL query or schema.
  """

  defstruct message: "", locations: []

  @type t :: %__MODULE__{
          message: String.t(),
          locations: [GraphqlQuery.Location.t()]
        }
end
