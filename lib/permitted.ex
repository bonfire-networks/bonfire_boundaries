defmodule Bonfire.Boundaries.Permitted do

  use Ecto.Schema
  alias Pointers.{Pointer, ULID}
  alias Bonfire.Data.AccessControl.Verb

  @primary_key false
  @foreign_key_type ULID
  schema "bonfire_boundaries_summary" do
    belongs_to :subject, Pointer, primary_key: true
    belongs_to :object, Pointer, primary_key: true
    belongs_to :verb, Verb, primary_key: true
    field :value, :boolean
  end

end
