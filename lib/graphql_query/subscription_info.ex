defmodule GraphqlQuery.SubscriptionInfo do
  @moduledoc """
  Represents information about a GraphQL subscription with its dependencies.

  This struct captures details about GraphQL subscriptions, including the
  subscription name and a list of fragments used within the subscription operation.
  """

  defstruct [:name, :fragments, :location]

  @type t :: %__MODULE__{
          name: String.t(),
          fragments: [String.t()],
          location: GraphqlQuery.Location.t() | nil
        }
end
