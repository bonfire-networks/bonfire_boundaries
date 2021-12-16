defmodule Bonfire.Boundaries.Controlleds do

  alias Bonfire.Data.AccessControl.Controlled
  import Bonfire.Boundaries
  import Ecto.Query

  def create(%{}=attrs) when not is_struct(attrs) do
    repo().insert(
      changeset(attrs),
      on_conflict: :nothing
    )
  end

  def changeset(c \\ %Controlled{}, attrs) do
    Controlled.changeset(c, attrs)
  end

  def list, do: repo().many(from(
    u in Controlled,
    left_join: acl in assoc(u, :acl),
    left_join: named in assoc(acl, :named),
    preload: [acl: [:named]]
  ))


end
