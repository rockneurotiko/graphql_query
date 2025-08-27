# defmodule Test.Schema do
#   use Absinthe.Schema

#   # Example data
#   @items %{
#     "foo" => %{id: "foo", name: "Foo"},
#     "bar" => %{id: "bar", name: "Bar"}
#   }

#   @desc "An item"
#   object :item do
#     field(:id, :id)
#     field(:name, :string)
#   end

#   query do
#     field :item, :item do
#       arg(:id, non_null(:id))

#       resolve(fn %{id: item_id}, _ ->
#         {:ok, @items[item_id]}
#       end)
#     end
#   end
# end
