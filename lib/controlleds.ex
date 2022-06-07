defmodule Bonfire.Boundaries.Controlleds do
  use Arrows
  import Bonfire.Boundaries.Integration
  import Ecto.Query
  import Where
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Cache
  alias Bonfire.Data.AccessControl.Controlled

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

  def list_on_object(object), do: list_on_objects([object])

  def list_on_objects(objects) when is_list(objects) do
    Cache.cached_preloads_for_objects("object_acl", objects, &do_list_on_objects/1)
  end

  defp do_list_on_objects(objects) when is_list(objects) and length(objects) >0 do
    repo().many(list_on_objects_q(objects))
    |> Map.new(fn c ->
      { # Map.new discards duplicates for the same key, which is convenient for now as we only display one ACL (note that the order_by in the `list_on_objects` query matters)
        Utils.e(c, :id, nil),
        Utils.e(c, :acl, nil)
      }
    end)
  end
  defp do_list_on_objects(_), do: %{}

  defp list_on_objects_q(objects, filter_acls \\ [:guests_may_see_read, :locals_may_interact, :locals_may_reply]) do
    filter_acls = filter_acls |> Enum.map(&Bonfire.Boundaries.Acls.get_id!/1)

    from c in Controlled,
    left_join: acl in assoc(c, :acl),
    left_join: named in assoc(acl, :named),
    where: c.acl_id in ^filter_acls,
    where: c.id in ^Utils.ulid(objects),
    order_by: [asc: c.acl_id],
    preload: [acl: {acl, named: named}]
  end

end
