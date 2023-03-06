defmodule Bonfire.Boundaries do
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration

  # alias Bonfire.Data.Identity.User
  # alias Bonfire.Boundaries.Circles
  # alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.Identity.Caretaker
  alias Bonfire.Boundaries.Summary
  alias Bonfire.Boundaries.Verbs
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Controlleds
  alias Bonfire.Boundaries.Queries
  alias Pointers
  # alias Pointers.Pointer
  import Queries, only: [boundarise: 3]
  import Ecto.Query
  import EctoSparkles

  def preset_name(boundaries) when is_list(boundaries) do
    debug(boundaries, "inputted")
    # Note: only one applies, in priority from most to least restrictive
    cond do
      "admins" in boundaries ->
        "admins"

      "mentions" in boundaries ->
        "mentions"

      "local" in boundaries ->
        "local"

      "federated" in boundaries ->
        # TODO: we should set a boundary based federated activity/object, rather than assuming
        "federated"

      "public" in boundaries ->
        "public"

      "open" in boundaries or "request" in boundaries or "invite" in boundaries or
          "visible" in boundaries ->
        boundaries

      true ->
        # debug(boundaries, "No preset boundary set")
        nil
    end
    |> debug("computed")
  end

  def preset_name(other) do
    boundaries_normalise(other)
    |> preset_name()
  end

  def boundaries_normalise(text) when is_binary(text) do
    text
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end

  def boundaries_normalise(list) when is_list(list) do
    list
  end

  def boundaries_normalise(other) do
    warn(other, "Invalid boundaries set")
    []
  end

  def list_object_acls(object) do
    Controlleds.list_on_object(object)
    |> Enum.map(& &1.acl)
  end

  def list_grants_on(things) do
    from(s in Summary,
      where: s.object_id in ^Types.ulids(things)
    )
    |> group_all_by_verb()
  end

  @doc "eg: `list_grants_on(id, [:see, :read])`"
  def list_grants_on(things, verbs) do
    verb_ids =
      List.wrap(verbs)
      |> Enum.map(fn
        slug when is_atom(slug) -> Verbs.get_id!(slug)
        id when is_binary(id) or is_map(id) -> ulid(id)
      end)

    verb_names =
      Enum.map(verb_ids, &Verbs.get(&1).verb)
      |> Enum.sort()
      |> debug()

    from(s in Summary,
      where: s.object_id in ^Types.ulids(things),
      where: s.verb_id in ^verb_ids
    )
    |> proload([:subject])
    |> group_all_by_verb()
    |> Enum.filter(&(&1.verbs == verb_names))
  end

  def my_grants_on(users, things) do
    from(s in Summary,
      where: s.subject_id in ^Types.ulids(users),
      where: s.object_id in ^Types.ulids(things)
    )
    |> group_all_by_verb()
  end

  defp group_all_by_verb(query) do
    query
    |> repo().all()
    |> Enum.group_by(&{&1.subject_id, &1.object_id, &1.value})
    |> for({_k, [v | _] = vs} <- ...) do
      Map.put(v, :verbs, Enum.map(vs, &Verbs.get!(&1.verb_id).verb) |> Enum.sort())
    end

    # |> Enum.map(&Map.take(&1, [:subject_id, :object_id, :verbs, :value]))
  end

  def acls_from_preset_boundary_names(presets) when is_list(presets),
    do: Enum.flat_map(presets, &acls_from_preset_boundary_names/1)

  def acls_from_preset_boundary_names(preset) do
    case preset do
      preset when is_binary(preset) ->
        acls = Config.get!(:preset_acls)[preset]

        if acls do
          acls
        else
          []
        end

      _ ->
        []
    end
  end

  def preset_boundary_from_acl(
        %{verbs: verbs, __typename: Bonfire.Data.AccessControl.Acl, id: acl_id} = _summary
      ) do
    {preset_boundary_role_from_acl(%{verbs: verbs}),
     preset_boundary_tuple_from_acl(%Acl{id: acl_id})}

    # |> debug("merged ACL + verbs")
  end

  def preset_boundary_from_acl(%{verbs: verbs} = _summary) do
    preset_boundary_role_from_acl(%{verbs: verbs})
  end

  def preset_boundary_from_acl(acl) do
    preset_boundary_tuple_from_acl(acl)
  end

  def preset_boundary_role_from_acl(%{verbs: verbs} = _summary) do
    # debug(summary)
    case Verbs.role_from_verb_names(verbs) do
      :caretaker -> {l("Caretaker"), l("Full permissions")}
      role -> {String.capitalize(to_string(role)), verbs}
    end
  end

  def preset_boundary_role_from_acl(other) do
    warn(other, "No pattern matched")
    nil
  end

  def preset_boundary_tuple_from_acl(acl, object_type \\ nil)

  def preset_boundary_tuple_from_acl(acl, %{__struct__: schema} = _object),
    do: preset_boundary_tuple_from_acl(acl, schema)

  def preset_boundary_tuple_from_acl(%Acl{id: acl_id} = _acl, Bonfire.Classify.Category) do
    # debug(acl)

    preset_acls = Config.get!(:preset_acls)

    open_acl_ids =
      preset_acls["open"]
      |> Enum.map(&Acls.get_id!/1)

    visible_acl_ids =
      preset_acls["visible"]
      |> Enum.map(&Acls.get_id!/1)

    cond do
      acl_id in open_acl_ids -> {"open", l("Open")}
      acl_id in visible_acl_ids -> {"visible", l("Visible")}
      true -> {"private", l("Private")}
    end
  end

  def preset_boundary_tuple_from_acl(%Acl{id: acl_id} = _acl, _object_type) do
    # debug(acl)

    preset_acls = Config.get!(:preset_acls_all)

    public_acl_ids =
      preset_acls["public"]
      |> Enum.map(&Acls.get_id!/1)

    local_acl_ids =
      preset_acls["local"]
      |> Enum.map(&Acls.get_id!/1)

    cond do
      acl_id in public_acl_ids -> {"public", l("Public")}
      acl_id in local_acl_ids -> {"local", l("Local Instance")}
      true -> {"mentions", l("Mentions")}
    end
  end

  def preset_boundary_tuple_from_acl(
        %{__typename: Bonfire.Data.AccessControl.Acl, id: acl_id} = _summary,
        object_type
      ) do
    preset_boundary_tuple_from_acl(%Acl{id: acl_id}, object_type)
  end

  def preset_boundary_tuple_from_acl(%{acl: acl}, object_type),
    do: preset_boundary_tuple_from_acl(acl, object_type)

  def preset_boundary_tuple_from_acl([acl], object_type),
    do: preset_boundary_tuple_from_acl(acl, object_type)

  def preset_boundary_tuple_from_acl(other, _object_type) do
    warn(other, "No pattern matched")
    nil
  end

  def set_boundaries(creator, object, opts)
      when is_list(opts) and (is_binary(object) or is_map(object)) do
    with {:ok, _pointer} <-
           Ecto.Changeset.cast(%Pointers.Pointer{id: ulid(object)}, %{}, [])
           |> Bonfire.Boundaries.Acls.cast(creator, opts)
           #  |> debug("ACL it")
           |> repo().update() do
      # debug(one_grant: grant)
      {:ok, :granted}
    end
  end

  @doc """
  Assigns the user as the caretaker of the given object or objects,
  replacing the existing caretaker, if any.
  """
  def take_care_of!(things, user) when is_list(things) do
    repo().upsert_all(
      Caretaker,
      Enum.map(things, &%{id: Types.ulid(&1), caretaker_id: Types.ulid(user)})
    )

    # |> debug

    Enum.map(things, fn thing ->
      case thing do
        %{caretaker: _} ->
          Map.put(thing, :caretaker, %Caretaker{
            id: thing.id,
            caretaker_id: Types.ulid(user),
            caretaker: user
          })

        _ ->
          thing
      end
    end)
  end

  def take_care_of!(thing, user), do: hd(take_care_of!([thing], user))

  def user_default_boundaries() do
    Config.get!(:user_default_boundaries)
  end

  def can?(_subject, can_verbs?, %{verbs: can_verbs!, value: true} = object_boundary)
      when is_list(can_verbs!) do
    warn(object_boundary, "WIP for preloaded object_boundary")
    Enum.all?(List.wrap(can_verbs?), &Enum.member?(can_verbs!, Verbs.get(&1)[:verb]))
  end

  def can?(subject, verbs, object)
      when is_map(object) or is_binary(object) or is_list(object) do
    debug(object, "check object")
    current_user = current_user(subject)
    current_user_id = ulid(current_user)

    creator_id =
      e(object, :created, :creator_id, nil) || e(object, :created, :creator, :id, nil) ||
        e(object, :creator_id, nil) || e(object, :creator, :id, nil)

    case (not is_nil(current_user_id) and creator_id == current_user_id) or
           pointer_permitted?(object,
             current_user: current_user,
             current_account: current_account(subject),
             verbs: verbs,
             ids_only: true
           ) do
      true ->
        true

      %{id: _} ->
        true

      other ->
        debug(verbs, "no permission to")
        debug(other)
        false
    end
  end

  def can?(_subject, _verbs, nil) do
    debug("object is nil")
    nil
  end

  def can?(_subject, _verbs, :skip) do
    debug("no object boundary data")
    nil
  end

  def can?(subject, verbs, :instance) do
    # cache needed for eg. for extension page
    key =
      "can:#{ulid(current_user(subject) || current_account(subject))}:#{inspect(verbs)}:instance"

    with :not_set <- Process.get(key, :not_set) |> debug("from cache?") do
      do_can_instance(subject, verbs, key)
    end
  end

  defp do_can_instance(subject, verbs, key) do
    val =
      can?(subject, verbs, Bonfire.Boundaries.Fixtures.instance_acl())
      |> debug("put in cache")

    Process.put(key, val)
    val
  end

  def pointer_permitted?(item, opts) do
    case ulid(item) do
      id when is_binary(id) ->
        load_query(id, e(opts, :ids_only, nil), opts ++ [limit: 1])
        |> repo().exists?()

      _ ->
        error(
          item,
          "Expected an object or ULID ID, could not check boundaries"
        )

        nil
    end
  end

  def load_pointer(item, opts) do
    case ulid(item) do
      id when is_binary(id) ->
        load_query(id, e(opts, :ids_only, nil), opts ++ [limit: 1])
        |> repo().one()

      _ ->
        error(
          item,
          "Expected an object or ULID ID, could not check boundaries"
        )

        nil
    end
  end

  @doc """
  Loads binaries according to boundaries (which are assumed to be ULID pointer IDs).
  Lists which are iterated and return a [sub]list with only permitted pointers.
  """
  def load_pointers(items, opts) when is_list(items) do
    # debug(items, "items")
    case ulid(items) do
      [] ->
        []

      nil ->
        []

      ids ->
        load_query(ids, e(opts, :ids_only, nil), opts)
        |> repo().many()
    end
  end

  defp load_query(ids, true, opts) do
    load_query(ids, nil, opts)
    |> select([main], [:id])
  end

  defp load_query(ids, _, opts) do
    from(p in Pointers.query_base(), where: p.id in ^List.wrap(ids))
    |> boundarise(id, opts)
  end
end
