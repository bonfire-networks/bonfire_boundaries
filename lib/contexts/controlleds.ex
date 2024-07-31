defmodule Bonfire.Boundaries.Controlleds do
  @moduledoc """
  An object is linked to one or more `Acl`s by the `Controlled` multimixin, which pairs an object ID with an ACL ID.
  Because it is a multimixin, a given object can have multiple ACLs applied. In the case of overlap, permissions are combined with `false` being prioritised.

  The `Controlled` multimixin link an object to one or more ACLs. This allows for applying multiple boundaries to the same object. In case of overlapping permissions, the system combines them following the logic described in `Bonfire.Boundaries`.

  The corresponding Ecto schema is `Bonfire.Data.AccessControl.Controlled` which is defined in a [seperate repo](https://github.com/bonfire-networks/bonfire_data_access_control).

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
  alias Bonfire.Boundaries.Grants
  # alias Bonfire.Boundaries.Controlleds
  alias Bonfire.Boundaries.Verbs
  alias Bonfire.Data.AccessControl.Controlled
  alias Bonfire.Data.AccessControl.Acl

  @doc """
  Creates a `Controlled` record with the given attributes.

  ## Examples

      iex> create(%{field: value})
      {:ok, %Controlled{}}

  """
  def create(%{} = attrs) when not is_struct(attrs) do
    repo().insert(
      changeset(attrs),
      on_conflict: :nothing
    )
  end

  @doc """
  Returns a changeset for a `Controlled` with the given attributes.

  ## Examples

      iex> changeset(%Controlled{}, %{field: value})
      %Ecto.Changeset{}

  """
  def changeset(c \\ %Controlled{}, attrs) do
    Controlled.changeset(c, attrs)
  end

  @doc """
  Lists ACLs applied to the given objects by the subject (current_user).

  ## Examples

      iex> list_on_objects_by_subject(objects, current_user)
      %{object1_id => [%Acl{}], object2_id => [%Acl{}]}

  """
  def list_on_objects_by_subject(objects, current_user) do
    repo().many(list_on_objects_by_subject_q(objects, current_user))
    |> Enum.reduce(%{}, fn c, acc ->
      id = ulid(c)
      # TODO: better
      Map.put(acc, id, Map.get(acc, id, []) ++ [e(c, :acl, nil) || %Acl{id: e(c, :acl_id, nil)}])
    end)
  end

  @doc """
  Lists ACLs applied to an object.
  Only call this as an admin or curator of the object.

  ## Examples

      iex> list_acls_on_object(object)
      [%Acl{}]
  """
  def list_acls_on_object(object, opts \\ [])

  def list_acls_on_object(%{} = object, opts) do
    exclude =
      e(
        opts,
        :exclude_ids,
        []
      ) ++ Acls.default_exclude_ids(false)

    object
    |> repo().maybe_preload(
      :controlled,
      force: true
    )
    |> debug()
    |> repo().maybe_preload(
      controlled: [
        acl: [
          :named,
          stereotyped: [:named]
        ]
      ]
    )
    |> Map.get(
      :controlled,
      []
    )
    |> Enum.reject(&(e(&1, :acl_id, nil) in exclude))
  end

  def list_acls_on_object(object, opts) do
    list_objects_q(object, opts)
    |> proload(
      acl:
        {"acl_",
         [
           :named,
           stereotyped: {"stereotyped_", [:named]}
         ]}
    )
    |> repo().many()
  end

  @doc """
  Lists ALL boundaries (ACLs and grants) applied to an object.
  Only call this as an admin or curator of the object.

  ## Examples

      iex> list_on_object(object)
      [%Boundary{}]
  """
  def list_on_object(object, opts \\ [])

  def list_on_object(%{} = object, opts) do
    exclude =
      e(
        opts,
        :exclude_ids,
        []
      ) ++ Acls.default_exclude_ids(false)

    object
    |> repo().maybe_preload(
      :controlled,
      force: true
    )
    |> debug()
    |> repo().maybe_preload(
      controlled: [
        acl: [
          :named,
          grants: [subject: [:named, :profile, :character]],
          stereotyped: [:named]
        ]
      ]
    )
    |> Map.get(
      :controlled,
      []
    )
    |> Enum.reject(&(e(&1, :acl_id, nil) in exclude))
  end

  def list_on_object(object, opts) do
    list_objects_q(object, opts)
    |> proload(
      acl:
        {"acl_",
         [
           :named,
           stereotyped: {"stereotyped_", [:named]},
           grants: [:verb, subject: {"subject_", [:named, :profile, :character]}]
         ]}
    )
    |> repo().many()
  end

  # def list_all, do: repo().many(list_q())

  @doc """
  Gets a preset ACL applied to an object, if any.

  ## Examples

      iex> get_preset_on_object(object)
      %ACL{}
  """
  def get_preset_on_object(object) do
    list_presets_on_objects_q([object])
    |> limit(1)
    |> repo().one()
  end

  @doc """
  Lists presets ACLs applied to the given objects.

  ## Examples

      iex> list_presets_on_objects(objects)
      %{object_id => %Preset{}}

  """
  def list_presets_on_objects(objects) do
    # FIXME: caching currently ends up with everything appearing to be public...
    # Cache.cached_preloads_for_objects("object_acl", objects, &do_list_presets_on_objects/1)
    do_list_presets_on_objects(objects)
  end

  defp do_list_presets_on_objects(objects)
       when is_list(objects) and length(objects) > 0 do
    repo().many(list_presets_on_objects_q(objects))
    |> debug()
    |> Map.new(fn c ->
      # Map.new discards duplicates for the same key, which is convenient for now as we only display one ACL (note that the order_by in the `list_on_objects` query matters)
      {
        e(c, :id, nil),
        e(c, :acl, nil) || %Acl{id: e(c, :acl_id, nil)}
      }
    end)
  end

  defp do_list_presets_on_objects(_), do: %{}

  @doc """
  Lists subjects who have been granted a given verb on specified object(s).

  ## Examples

      iex> list_subjects_by_verb(objects, :read)

      iex> list_subjects_by_verb(objects, :edit, false)
  """
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

  @doc """
  Lists grants of a given verb on specified object(s).

  ## Examples

      iex> list_grants_by_verbs(objects, :read)

      iex> list_grants_by_verbs(objects, :edit, false)
  """
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

  def list_q(opts \\ []) do
    exclude =
      e(
        opts,
        :exclude_ids,
        []
      ) ++ Acls.default_exclude_ids(false)

    from(
      c in Controlled,
      left_join: acl in assoc(c, :acl),
      as: :acl,
      left_join: stereotyped in assoc(acl, :stereotyped),
      as: :stereotyped,
      where:
        acl.id not in ^exclude and
          (is_nil(stereotyped.id) or
             stereotyped.stereotype_id not in ^exclude),
      order_by: [asc: c.acl_id]
      # preload: [acl: {acl, named: named}]
      # preload: [acl: acl]
    )
  end

  # TODO: instead of preloading named from DB we can use names from Config

  defp list_objects_q(objects, opts \\ []) do
    where(list_q(opts), [c], c.id in ^ulids(objects))
  end

  defp list_on_objects_by_subject_q(objects, current_user) do
    list_objects_q(objects)
    |> proload(acl: [:named, stereotyped: {"stereotyped_", [:named]}, grants: [:verb]])
    |> where(
      [c, grants: grants],
      grants.subject_id == ^ulid(current_user) and c.acl_id not in ^Acls.preset_acl_ids()
    )
  end

  defp list_on_objects_by_verb_q(objects, verbs, value \\ true) do
    list_objects_q(objects)
    |> proload(
      acl: [
        :named,
        stereotyped: {"stereotyped_", [:named]},
        grants: [:verb, subject: {"subject_", [:named, :profile, :character]}]
      ]
    )
    |> where(
      [c, grants: grants],
      grants.verb_id in ^ulids(verbs) and grants.value == ^value
    )
  end

  defp list_presets_on_objects_q(objects) do
    list_objects_q(objects)
    |> where([c], c.acl_id in ^Acls.preset_acl_ids())
  end

  @doc """
  Removes the given ACLs from an object.

  ## Examples

      iex> remove_acls(object, acls)
  """
  def remove_acls(_object, acls)
      when is_nil(acls) or acls == [],
      do: error("No acl ID provided, so could not remove")

  def remove_acls(object, acls) do
    from(e in Controlled,
      where:
        e.id == ^ulid!(object) and
          e.acl_id in ^ulids_or(acls, &acl_id/1)
    )
    |> repo().delete_all()
  end

  defp acl_id(%{acl_id: id}), do: id
  defp acl_id(id), do: Bonfire.Boundaries.Acls.get_id(id)

  @doc """
  Adds the given ACL to an object.

  ## Examples

      iex> add_acls(object, :acl)
      {:ok, %Controlled{}}

  """
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

  @doc """
  Grants a role to a subject for an object.

  ## Examples

      iex> grant_role(subject_id, object, :editor)
      {:ok, %Grant{}}

  """
  def grant_role(subject_id, object, role, opts \\ []) do
    with {:ok, acl} <- Acls.get_or_create_object_custom_acl(object, current_user(opts)) do
      Grants.grant_role(subject_id, acl, role, opts)
    end
  end
end
