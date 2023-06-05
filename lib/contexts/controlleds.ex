defmodule Bonfire.Boundaries.Controlleds do
  @moduledoc """
  An object is linked to one or more `Acl`s by the `Controlled` multimixin, which pairs an object ID with an ACL ID. Because it is a multimixin, a given object can have multiple ACLs applied. In the case of overlap, permissions are combined with `false` being prioritised.
  """
  use Arrows
  import Bonfire.Boundaries.Integration
  import Ecto.Query
  import EctoSparkles
  import Untangle
  use Bonfire.Common.Utils
  # alias Bonfire.Common.Config
  # alias Bonfire.Common.Cache
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Controlleds
  alias Bonfire.Boundaries.Verbs
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

  def list_on_objects_by_subject(objects, current_user) do
    repo().many(list_on_objects_by_subject_q(objects, current_user))
    |> Enum.reduce(%{}, fn c, acc ->
      id = ulid(c)
      # TODO: better
      Map.put(acc, id, Map.get(acc, id, []) ++ [e(c, :acl, nil)])
    end)
  end

  @doc """
  List ALL boundaries applied to an object.
  Only call this as an admin or curator of the object.
  """
  def list_on_object(%{} = object) do
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
    )
    |> Map.get(
      :controlled,
      []
    )

    # |> debug
  end

  def list_on_object(object) do
    repo().many(list_q(object))
  end

  # def list_all, do: repo().many(list_q())

  def get_preset_on_object(object) do
    list_presets_on_objects_q([object])
    |> limit(1)
    |> repo().one()
  end

  def list_presets_on_objects(objects) do
    # FIXME: caching currently ends up with everything appearing to be public...
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

  def list_subjects_by_verb(objects, verb, value \\ true) when is_binary(verb) or is_atom(verb) do
    list_on_objects_by_verb_q(objects, Verbs.ids(verb), value)
    |> repo().many()
    # |> debug()
    |> Map.new(fn c ->
      # note: Map.new discards duplicates for the same key
      {
        "#{e(c, :acl, :grants, :verb_id, nil)}-#{e(c, :acl, :grants, :subject_id, nil)}",
        e(c, :acl, :grants, :subject, nil)
      }
    end)
    |> Map.values()
  end

  def list_grants_by_verbs(objects, verbs, value \\ true) when is_list(verbs) do
    list_on_objects_by_verb_q(objects, Verbs.ids(verbs), value)
    |> repo().many()
    # |> debug()
    |> Map.new(fn c ->
      # note: Map.new discards duplicates for the same key
      {
        "#{e(c, :acl, :grants, :verb_id, nil)}-#{e(c, :acl, :grants, :subject_id, nil)}",
        e(c, :acl, :grants, nil)
      }
    end)
  end

  def list_q,
    do:
      from(
        c in Controlled,
        left_join: acl in assoc(c, :acl),
        as: :acl,
        # left_join: named in assoc(acl, :named),
        order_by: [asc: c.acl_id],
        # preload: [acl: {acl, named: named}]
        preload: [acl: acl]
      )

  # TODO: instead of preloading named from DB we can use names from Config

  defp list_q(objects) do
    where(list_q(), [c], c.id in ^ulids(objects))
  end

  defp list_on_objects_by_subject_q(objects, current_user) do
    list_q(objects)
    |> proload(acl: [:stereotyped, :grants])
    |> where(
      [c, grants: grants],
      grants.subject_id == ^ulid(current_user) and c.acl_id not in ^Acls.preset_acl_ids()
    )
  end

  defp list_on_objects_by_verb_q(objects, verbs, value \\ true) do
    list_q(objects)
    |> proload(acl: [grants: [:verb, subject: [:profile, :character]]])
    |> where(
      [c, grants: grants],
      grants.verb_id in ^ulids(verbs) and grants.value == ^value
    )
  end

  defp list_presets_on_objects_q(objects) do
    list_q(objects)
    |> where([c], c.acl_id in ^Acls.preset_acl_ids())
  end

  def remove_acls(_object, acls)
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

  def grant_role(subject_id, object, role, opts \\ []) do
    with {:ok, acl} <- Acls.get_or_create_object_custom_acl(object, current_user(opts)) do
      Controlleds.grant_role(subject_id, acl, role, opts)
    end
  end
end
