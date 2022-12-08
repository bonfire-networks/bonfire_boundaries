defmodule Bonfire.Boundaries.Controlleds do
  use Arrows
  import Bonfire.Boundaries.Integration
  import Ecto.Query
  import Untangle
  import Bonfire.Common.Utils
  alias Bonfire.Common.Config
  alias Bonfire.Common.Cache
  alias Bonfire.Data.AccessControl.Controlled

  def create(%{} = attrs) when not is_struct(attrs) do
    repo().insert(
      changeset(attrs),
      on_conflict: :nothing
    )
  end

  def changeset(c \\ %Controlled{}, attrs) do
    Controlled.changeset(c, attrs)
  end

  def list, do: repo().many(list_q())

  def list_q,
    do:
      from(
        c in Controlled,
        left_join: acl in assoc(c, :acl),
        left_join: named in assoc(acl, :named),
        order_by: [asc: c.acl_id],
        preload: [acl: {acl, named: named}]
      )

  @doc """
  List all boundaries applied to an object.
  Only call this as an admin or curator of the object.
  """
  def list_on_object(%{} = object) do
    Map.get(
      repo().maybe_preload(
        object,
        [
          controlled: [
            acl: [
              :named,
              grants: [subject: [:named, :profile, :character]],
              stereotyped: [:named]
            ]
          ]
        ],
        force: true
      ),
      :controlled,
      []
    )

    # |> debug
  end

  # def list_on_object(object) do
  #   repo().many(list_q(object))
  # end

  defp list_q(objects) do
    where(list_q(), [c], c.id in ^ulids(objects))
  end

  def get_preset_on_object(object) do
    list_presets_on_objects_q([object])
    |> limit(1)
    |> repo().one()
  end

  def list_presets_on_objects(objects) do
    # FIXME: caching ends up with everything appearing to be public
    # Cache.cached_preloads_for_objects("object_acl", objects, &do_list_presets_on_objects/1)
    do_list_presets_on_objects(objects)
  end

  defp do_list_presets_on_objects(objects)
       when is_list(objects) and length(objects) > 0 do
    repo().many(list_presets_on_objects_q(objects))
    |> Map.new(fn c ->
      # Map.new discards duplicates for the same key, which is convenient for now as we only display one ACL (note that the order_by in the `list_on_objects` query matters)
      {
        e(c, :id, nil),
        e(c, :acl, nil)
      }
    end)
  end

  defp do_list_presets_on_objects(_), do: %{}

  defp list_presets_on_objects_q(objects) do
    filter_acls =
      Config.get(:public_acls_on_objects, [
        :guests_may_see_read,
        :locals_may_interact,
        :locals_may_reply
      ])
      |> Enum.map(&Bonfire.Boundaries.Acls.get_id!/1)

    list_q(objects)
    |> where([c], c.acl_id in ^filter_acls)
  end

  def remove_acls(object, acls)
      when is_nil(acls) or (is_list(acls) and length(acls) == 0),
      do: error("No acl ID provided, so could not remove")

  def remove_acls(object, acls) do
    from(e in Controlled,
      where:
        e.id == ^ulid!(object) and
          e.acl_id in ^ulids_or(acls, &Bonfire.Boundaries.Acls.get_id/1)
    )
    |> repo().delete_all()
  end

  # TODO: move somewhere re-usable
  def ulids_or(objects, fallback_or_fun) when is_list(objects) do
    Enum.map(objects, &ulids_or(&1, fallback_or_fun))
  end

  def ulids_or(object, fun) when is_function(fun) do
    List.wrap(ulid(object) || fun.(object))
  end

  def ulids_or(object, fallback) do
    List.wrap(ulid(object) || fallback)
  end

  def add_acls(object, acl) when is_atom(acl) do
    Bonfire.Boundaries.Acls.get_id!(acl)
    |> add_acls(object, ...)
  end

  def add_acls(object, acl) when not is_list(acl) do
    create(%{id: ulid!(object), acl_id: ulid!(acl)})
  end

  def add_acls(object, acls) when is_list(acls) do
    # TODO: optimise
    Enum.map(acls, &add_acls(object, &1))
  end
end
