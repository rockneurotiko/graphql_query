defmodule GraphqlQuery.ValidationWarning do
  @moduledoc """
  Represents a validation warning returned from the Rust NIF layer.

  Warnings differ from errors in that they do not prevent a query from being
  executed — they indicate best-practice violations or deprecated usage.

  The `kind` field identifies the warning type so the Elixir layer can format
  each kind appropriately. This design allows new warning types to be added in
  the future without breaking existing callers.

  ## Warning kinds

    * `"deprecated_field"` — the query uses a field marked `@deprecated` in the
      schema. The `message` field contains the deprecation reason (from the
      `@deprecated(reason: ...)` argument), `field` is the field name, and
      `parent_type` is the containing GraphQL type.
  """

  defstruct [:kind, :message, :field, :parent_type, locations: []]

  @type t :: %__MODULE__{
          kind: String.t(),
          message: String.t(),
          field: String.t(),
          parent_type: String.t(),
          locations: [GraphqlQuery.Location.t()]
        }
end
