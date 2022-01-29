defmodule Bonfire.Boundaries.Controlleds do

  alias Bonfire.Data.AccessControl.Controlled
  import Bonfire.Boundaries
  import Ecto.Query
  alias Bonfire.Common.Utils

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

  def list_on_object(object), do: list_on_object([object])

  def list_on_objects(objects) do
    repo().many(list_on_objects_q(objects))
  end

  def list_on_objects_q(objects, filter_acls \\ [:guests_may_see, :locals_may_interact, :locals_may_reply]) do
    filter_acls = filter_acls |> Bonfire.Boundaries.Acls.get_id!()

    from c in Controlled,
    left_join: acl in assoc(c, :acl),
    left_join: named in assoc(acl, :named),
    where: c.acl_id in ^filter_acls,
    where: c.object_id in ^Utils.ulid(objects)
  end

end
