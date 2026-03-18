defmodule GraphqlQuery.SchemaInformation do
  @moduledoc "Schema information passed to Rust NIFs for query/fragment validation."

  defstruct [:schema, :path, federation: false, ignore_errors: false]

  @type t :: %__MODULE__{
          schema: String.t(),
          path: String.t() | nil,
          federation: boolean(),
          ignore_errors: boolean()
        }
end
