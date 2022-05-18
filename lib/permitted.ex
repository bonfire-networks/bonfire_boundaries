# defmodule Bonfire.Boundaries.Permitted do

#   use Ecto.Schema
#   alias Pointers.{Pointer, ULID}
#   # alias Bonfire.Data.AccessControl.Verb

#   @primary_key false
#   @foreign_key_type ULID
#   schema "bonfire_boundaries_permitted" do
#     belongs_to :subjects, :integer
#     belongs_to :object, Pointer, primary_key: true
#     field :verbs, {:array, ULID}
#   end

# end
