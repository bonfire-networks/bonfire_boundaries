defmodule Bonfire.Boundaries.SeeRead do

  use Ecto.Schema
  alias Pointers.{Pointer, ULID}

  @primary_key false
  @foreign_key_type ULID
  schema "boundaries_see_read" do
    belongs_to :subject, Pointer,
      on_replace: :update,
      primary_key: true,
      type: ULID
    belongs_to :object, Pointer,
      on_replace: :update,
      primary_key: true,
      type: ULID
    field :can_see?,  :boolean, source: :can_see
    field :can_read?, :boolean, source: :can_read
  end

end
