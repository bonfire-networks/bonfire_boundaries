defmodule Bonfire.Boundaries do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration

  # alias Bonfire.Data.Identity.User
  alias Bonfire.Boundaries.Circles
  # alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.Identity.Caretaker
  alias Bonfire.Boundaries.Summary
  alias Bonfire.Boundaries.Verbs
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Controlleds
  alias Bonfire.Boundaries.Roles
  alias Bonfire.Boundaries.Queries
  alias Needle
  alias Bonfire.Data.AccessControl.Stereotyped
  alias Needle.Pointer
  import Queries, only: [boundarise: 3]
  import Ecto.Query
  # import EctoSparkles

  @skip_object_placeholders [:skip, :skip_boundary_check, :loading]

  @doc """
  Returns the name of a preset boundary given a list of boundaries or other boundary representation.

  ## Examples

      iex> Bonfire.Boundaries.preset_name(["admins", "mentions"])
      "admins"

      iex> Bonfire.Boundaries.preset_name("public_remote", true)
      "public_remote"
  """
  def preset_name(boundaries, include_remote? \\ false)

  def preset_name(boundaries, include_remote?) when is_list(boundaries) do
    debug(boundaries, "inputted")
    # Note: only one applies, in priority from most to least restrictive
    cond do
      "admins" in boundaries ->
        "admins"

      "mentions" in boundaries ->
        "mentions"

      "local" in boundaries ->
        "local"

      "public" in boundaries ->
        "public"

      "public_remote" in boundaries ->
        # TODO: better
        if include_remote?, do: "public_remote", else: "public"

      "open" in boundaries or "request" in boundaries or "invite" in boundaries or
          "visible" in boundaries ->
        boundaries

      "private" in boundaries ->
        "private"

      true ->
        # debug(boundaries, "No preset boundary set")
        nil
    end
    |> debug("computed")
  end

  def preset_name(other, include_remote?) do
    boundaries_normalise(other)
    |> preset_name(include_remote?)
  end

  @doc """
  Returns custom boundaries or a default set of boundaries to use

  ## Examples

      iex> Bonfire.Boundaries.boundaries_or_default(["local"])
      ["local"]

      iex> Bonfire.Boundaries.boundaries_or_default(nil, current_user: me)
      [{"public", "Public"}]
  """
  def boundaries_or_default(to_boundaries, context \\ [])

  def boundaries_or_default(to_boundaries, _)
      when is_list(to_boundaries) and to_boundaries != [] do
    to_boundaries
  end

  def boundaries_or_default(to_boundaries, _)
      when is_tuple(to_boundaries) do
    [to_boundaries]
  end

  def boundaries_or_default(_, context) do
    default_boundaries(context)
  end

  @doc """
  Returns default boundaries to use based on the provided context.

  ## Examples

      iex> Bonfire.Boundaries.default_boundaries()
      [{"public", "Public"}]

      iex> Bonfire.Boundaries.default_boundaries(current_user: me)
      [{"local", "Local"}]
  """
  def default_boundaries(context \\ []) do
    # default boundaries for new stuff
    case Settings.get([:ui, :boundary_preset], :public, context) do
      :public ->
        [{"public", l("Public")}]

      :local ->
        [{"local", l("Local")}]

      :mentions ->
        [{"mentions", l("Mentions")}]

      :private ->
        [{"private", l("Private")}]

      other when is_binary(other) or is_atom(other) ->
        # debug(context, "zzzz")
        other = other |> to_string()
        [{other, e(context, :my_acls, other, nil) || other}]

      other ->
        other
    end
  end

  @doc """
  Normalizes boundaries represented as text or list.

  ## Examples

      iex> Bonfire.Boundaries.boundaries_normalise("local,public")
      ["local", "public"]

      iex> Bonfire.Boundaries.boundaries_normalise(["local", "public"])
      ["local", "public"]
  """
  def boundaries_normalise(text) when is_binary(text) do
    text
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end

  def boundaries_normalise(list) when is_list(list) do
    list
  end

  def boundaries_normalise(%Bonfire.Data.AccessControl.Acl{id: id}) do
    [id]
  end

  def boundaries_normalise(other) do
    warn(other, "Invalid boundaries set")
    []
  end

  @doc """
  Lists ACLs for a given object.

  ## Examples

      iex> Bonfire.Boundaries.list_object_acls(%{id: 1})
      [%Bonfire.Data.AccessControl.Acl{id: 42}]
  """
  def list_object_acls(object, opts \\ []) do
    Controlleds.list_acls_on_object(object, opts)
    # |> debug()
    |> Enum.map(& &1.acl)
  end

  def object_public?(object) do
    # FIXME: use `get_preset_on_object` instead of loading them all, or at least only load the IDs
    acls =
      list_object_acls(object)
      |> debug("post_acls")
      |> object_acls_public?()
  end

  def object_acls_public?(acls) do
    public_acl_ids = Bonfire.Boundaries.Acls.remote_public_acl_ids()
    Enum.any?(acls, fn %{id: acl_id} -> acl_id in public_acl_ids end)
  end

  @doc """
  Lists boundaries (ACLs and grants) for a given object 

      iex> Bonfire.Boundaries.list_object_boundaries(%{id: 1})
      [%Bonfire.Data.AccessControl.Acl{id: 42, grants: [...]}]
  """
  def list_object_boundaries(object, opts \\ []) do
    Controlleds.list_on_object(object, opts)
    # |> debug()
    |> Enum.map(& &1.acl)
  end

  def boundaries_on_objects(list_of_ids, current_user) do
    boundaries_on_objects(
      list_of_ids,
      Controlleds.list_presets_on_objects(list_of_ids),
      current_user
    )
  end

  def boundaries_on_objects(list_of_ids, presets, current_user) do
    if not is_nil(current_user) do
      # display user's computed permission if we have current_user
      case users_grants_on(current_user, list_of_ids) do
        custom when is_list(custom) and custom != [] ->
          custom
          |> Map.new(&{&1.object_id, Map.take(&1, [:verbs, :value])})
          |> debug("my_grants_on")
          |> deep_merge(presets || [], replace_lists: false)
          |> debug("merged boundaries")

        _empty ->
          presets
      end
    else
      presets
    end
  end

  def boundary_on_object(id, current_user) do
    boundary_on_object(id, Controlleds.get_preset_on_object(id), current_user)
  end

  def boundary_on_object(id, preset \\ nil, current_user) do
    if not is_nil(current_user) do
      # display user's computed permission if we have current_user
      case users_grants_on(current_user, id) do
        custom when is_list(custom) and custom != [] ->
          custom
          |> debug("users_grants_on")
          |> List.first()
          |> Map.take([:verbs, :value])
          |> debug("my_grants_on")
          |> Map.merge(preset || %{})
          |> debug("merged boundaries")

        _empty ->
          preset
      end
    else
      preset
    end
  end

  @doc """
  Lists grants for a given set of objects.

  ## Examples

      iex> Bonfire.Boundaries.list_grants_on([1, 2, 3])
  """
  def list_grants_on(things) do
    from(s in Summary,
      where: s.object_id in ^Types.uids(things)
    )
    |> all_grouped_by_verb()
  end

  @doc """
  Lists grants for a given set of objects and verbs.

  ## Examples

      iex> Bonfire.Boundaries.list_grants_on([1, 2, 3], [:see, :read])
  """
  def list_grants_on(things, verbs) do
    from(s in Summary,
      where: s.object_id in ^Types.uids(things)
    )
    |> filter_grants_by_verbs(verbs)
  end

  @doc """
  Lists grants for a given set of users on a set of objects.

  ## Examples

      iex> Bonfire.Boundaries.users_grants_on([%{id: 1}], [%{id: 2}])
  """
  def users_grants_on(users, things) do
    query_users_grants_on(users, things)
    |> all_grouped_by_verb()
  end

  @doc """
  Lists grants for a given set of users on a set of objects, filtered by verbs.

  ## Examples

      iex> Bonfire.Boundaries.users_grants_on([%{id: 1}], [%{id: 2}], [:see, :read])
      [%Bonfire.Boundaries.Summary{object_id: 2, subject_id: 1}]
  """
  def users_grants_on(users, things, verbs) do
    query_users_grants_on(users, things)
    |> filter_grants_by_verbs(verbs)
  end

  defp query_users_grants_on(users, things) do
    from(s in Summary,
      where: s.object_id in ^Types.uids(things),
      where: s.subject_id in ^Types.uids(users)
    )
  end

  defp filter_grants_by_verbs(query, verbs) do
    verb_ids =
      List.wrap(verbs)
      |> Enum.map(fn
        slug when is_atom(slug) -> Verbs.get_id!(slug)
        id when is_binary(id) or is_map(id) -> uid(id)
      end)

    verb_names =
      Enum.map(verb_ids, &Verbs.get(&1).verb)
      |> Enum.sort()

    # |> debug()

    from(s in query,
      where: s.verb_id in ^verb_ids
    )
    |> all_grouped_by_verb()
    |> Enum.filter(&(&1.verbs == verb_names))
  end

  defp all_grouped_by_verb(query) do
    query
    |> repo().all()
    |> Enum.group_by(&{&1.subject_id, &1.object_id, &1.value})
    |> for({_k, [v | _] = vs} <- ...) do
      Map.put(v, :verbs, Enum.map(vs, &Verbs.get!(&1.verb_id).verb) |> Enum.sort())
    end

    # |> Enum.map(&Map.take(&1, [:subject_id, :object_id, :verbs, :value]))
  end

  @doc """
  Returns ACLs for a set of preset boundary names.

  ## Examples

      iex> Bonfire.Boundaries.acls_from_preset_boundary_names(["public"])
  """
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

  @doc """
  Converts an ACL to a preset boundary name based on the object type.

  ## Examples

      iex> Bonfire.Boundaries.preset_boundary_from_acl(%Bonfire.Data.AccessControl.Acl{id: 1})
      {"public", "Public"}
      
  """
  def preset_boundary_from_acl(acl, object_type \\ nil)

  def preset_boundary_from_acl(
        %{verbs: verbs, __typename: Bonfire.Data.AccessControl.Acl, id: acl_id} = _summary,
        object_type
      ) do
    {Roles.preset_boundary_role_from_acl(%{verbs: verbs}),
     preset_boundary_tuple_from_acl(%Acl{id: acl_id}, object_type)}

    # |> debug("merged ACL + verbs")
  end

  def preset_boundary_from_acl(%{verbs: verbs} = _summary, _object_type) do
    Roles.preset_boundary_role_from_acl(%{verbs: verbs})
  end

  def preset_boundary_from_acl(acl, object_type) do
    preset_boundary_tuple_from_acl(acl, object_type)
  end

  @doc """
  Converts an ACL to a preset boundary tuple based on the object type.

  ## Examples

      iex> Bonfire.Boundaries.preset_boundary_tuple_from_acl(%Bonfire.Data.AccessControl.Acl{id: 1})
      {"public", "Public"}

      iex> Bonfire.Boundaries.preset_boundary_tuple_from_acl(%Bonfire.Data.AccessControl.Acl{id: 1}, :group)
      {"open", "Open"}
  """
  def preset_boundary_tuple_from_acl(acl, object_type \\ nil, opts \\ [])

  def preset_boundary_tuple_from_acl(acl, %{__struct__: schema} = _object, opts),
    do: preset_boundary_tuple_from_acl(acl, schema, opts)

  def preset_boundary_tuple_from_acl(%Acl{id: acl_id} = _acl, object_type, opts)
      when object_type in [Bonfire.Classify.Category, :group] do
    # debug(acl)

    preset_acls = Config.get!(:preset_acls_match)

    open_acl_ids =
      preset_acls["open"]
      |> Enum.map(&Acls.get_id!/1)

    visible_acl_ids =
      preset_acls["visible"]
      |> Enum.map(&Acls.get_id!/1)

    cond do
      acl_id in visible_acl_ids -> {"visible", l("Visible")}
      acl_id in open_acl_ids -> {"open", l("Open")}
      true -> opts[:custom_tuple] || {"private", l("Private")}
    end
  end

  def preset_boundary_tuple_from_acl(%Acl{id: acl_id} = _acl, _object_type, opts) do
    preset_acls = Config.get!(:preset_acls_match)

    public_acl_ids = Acls.preset_acl_ids("public", preset_acls)
    local_acl_ids = Acls.preset_acl_ids("local", preset_acls)

    cond do
      acl_id in public_acl_ids -> {"public", l("Public")}
      acl_id in local_acl_ids -> {"local", l("Local Instance")}
      true -> opts[:custom_tuple] || {"mentions", l("Mentions")}
    end
  end

  def preset_boundary_tuple_from_acl(
        %{__typename: Bonfire.Data.AccessControl.Acl, id: acl_id} = _summary,
        object_type,
        opts
      ) do
    preset_boundary_tuple_from_acl(%Acl{id: acl_id}, object_type, opts)
  end

  def preset_boundary_tuple_from_acl(%{acl: %{id: _} = acl}, object_type, opts),
    do: preset_boundary_tuple_from_acl(acl, object_type, opts)

  def preset_boundary_tuple_from_acl(%{acl_id: acl}, object_type, opts),
    do: preset_boundary_tuple_from_acl(acl, object_type, opts)

  def preset_boundary_tuple_from_acl([acl], object_type, opts),
    do: preset_boundary_tuple_from_acl(acl, object_type, opts)

  def preset_boundary_tuple_from_acl(acls, object_type, opts) when is_list(acls) do
    # TODO: optimise
    presets =
      Enum.map(acls, fn acl ->
        preset_boundary_tuple_from_acl(acl, object_type, opts)
      end)
      |> Enum.uniq()

    cond do
      {"public", l("Public")} in presets -> {"public", l("Public")}
      {"local", l("Local Instance")} in presets -> {"local", l("Local Instance")}
      true -> opts[:custom_tuple] || {"mentions", l("Mentions")}
    end
  end

  def preset_boundary_tuple_from_acl(other, object_type, opts) do
    case Types.uid(other) do
      nil ->
        warn(other, "No boundary pattern matched")

        opts[:custom_tuple] || {"mentions", l("Mentions")}

      id ->
        preset_boundary_tuple_from_acl(%Acl{id: id}, object_type, opts)
    end
  end

  @doc """
  Sets or replace boundaries for a given object.

  ## Set boundaries on a black object

      iex> Bonfire.Boundaries.set_boundaries(%User{id: 1}, %{id: 2}, [boundary: "public"])
      {:ok, :granted}
      
  ## Replace boundaries on an existing object that previously had a preset applied

      iex> Bonfire.Boundaries.set_boundaries(%User{id: 1}, %{id: 2}, [boundary: "local", remove_previous_preset: "public"])
      {:ok, :granted}
  """
  def set_boundaries(creator, object, opts)
      when is_list(opts) and is_struct(object) do
    if opts[:to_boundaries] == "private" do
      with {num, nil} <- Bonfire.Boundaries.Controlleds.remove_all_acls(object) do
        {:ok, num}
      end
    else
      case opts[:remove_previous_preset] do
        nil ->
          with {:ok, _pointer} <- Acls.set(object, creator, opts) do
            {:ok, :granted}
          end

        previous_preset ->
          replace_boundaries(creator, object, previous_preset, opts)
      end
    end
  end

  defp replace_boundaries(creator, object, previous_preset, opts)
       when is_list(opts) and is_struct(object) do
    with object <-
           object
           # |> repo().maybe_preload(:controlled)
           |> repo().maybe_preload(created: [:creator])
           |> repo().maybe_preload(:creator),
         :ok <-
           maybe_remove_previous_preset(
             e(object, :created, :creator, nil) || e(object, :created, :creator_id, nil) ||
               e(object, :creator, nil) || e(object, :creator_id, nil) || creator,
             object,
             previous_preset
           ),
         {:ok, _pointer} <- Acls.set(object, creator, opts) do
      {:ok, :granted}
    end
  end

  defp maybe_remove_previous_preset(creator, object, [preset]) do
    maybe_remove_previous_preset(creator, object, preset)
  end

  defp maybe_remove_previous_preset(creator, object, {preset, _description})
       when is_binary(preset) and preset != "mentions" do
    debug(preset, "WIP")

    Acls.base_acls_from_preset(creator, preset)
    |> debug("base_acls_from_preset to remove")
    |> Bonfire.Boundaries.Controlleds.remove_acls(
      object,
      ...
    )
    |> debug("removed?")

    :ok
  end

  defp maybe_remove_previous_preset(_, _, preset) do
    warn(preset, "could not remove previous preset")
    :ok
  end

  @doc """
  Assigns the user as the caretaker of the given object or objects, replacing the existing caretaker, if any.

  ## Examples

      iex> Bonfire.Boundaries.take_care_of!([%{id: 1}], %{id: 2})
      [%{id: 1, caretaker: %{id: 1, caretaker_id: 2, caretaker: %{id: 2}}}]
  """
  def take_care_of!(things, user) when is_list(things) do
    repo().upsert_all(
      Caretaker,
      Enum.map(things, &%{id: Types.uid(&1), caretaker_id: Types.uid(user)})
    )
    |> debug("upserted caretakers")

    Enum.map(things, fn thing ->
      case thing do
        %{caretaker: _} ->
          Map.put(thing, :caretaker, %Caretaker{
            id: thing.id,
            caretaker_id: Types.uid(user),
            caretaker: user
          })

        _ ->
          thing
      end
    end)
  end

  def take_care_of!(thing, user), do: hd(take_care_of!([thing], user))

  @doc """
  Returns the default boundaries to be set for new users from config.
  """
  def user_default_boundaries(true = _local?) do
    Config.get!(:user_default_boundaries)
    |> debug("init for local actor")
  end

  def user_default_boundaries(_) do
    Config.get!(:remote_user_boundaries)
    |> debug("init for remote actor")
  end

  @doc """
  Checks if a subject has permission to conduct the specified action(s)/verb(s) on an object.

  ## Examples

      iex> Bonfire.Boundaries.can?(%User{id: 1}, [:see], %{id: 2})
      false
  """
  def can?(subject, verbs, object, opts \\ [])

  # just for typos ;)
  def can?(subject, can_verbs?, :instance_wide, opts),
    do: can?(subject, can_verbs?, :instance, opts)

  def can?(subject, can_verbs?, %{verbs: can_verbs!, value: true} = object_boundary, opts)
      when is_list(can_verbs!) do
    debug(object_boundary, " preloaded object_boundary")

    skip? = Queries.skip_boundary_check?(opts)

    skip? =
      skip? == true ||
        (skip? == :admins and
           Bonfire.Common.Utils.maybe_apply(Bonfire.Me.Accounts, :is_admin?, [subject],
             fallback_return: nil
           )) ||
        Enum.all?(List.wrap(can_verbs?), &Enum.member?(can_verbs!, Verbs.get(&1)[:verb]))
  end

  def can?(circle_name, verbs, object, opts) when is_atom(circle_name) do
    # lookup if a built-in circle (eg. local users) has permission (note that some circle members may NOT have permission if they're also in another circle with negative permissions)
    can?([current_user: Circles.get_id(circle_name)], verbs, object, opts)
  end

  def can?(subject, verbs, object, opts)
      when is_map(object) or is_binary(object) or is_list(object) do
    skip? =
      Queries.skip_boundary_check?(opts)
      |> debug("check object?")

    skip? =
      skip? == true ||
        (skip? == :admins and
           Bonfire.Common.Utils.maybe_apply(Bonfire.Me.Accounts, :is_admin?, [subject],
             fallback_return: nil
           )) ||
        (
          current_user = current_user(subject)
          current_user_id = id(current_user)

          {first_object, objects} =
            if is_list(object) do
              objects =
                Enum.reject(object, fn o -> is_nil(o) or o in @skip_object_placeholders end)

              {List.first(objects), objects}
            else
              {object, nil}
            end

          creator_id =
            if is_map(first_object),
              # TODO: include caretaker
              do:
                e(first_object, :created, :creator_id, nil) ||
                  e(first_object, :created, :creator, :id, nil) ||
                  e(first_object, :creator_id, nil) || e(first_object, :creator, :id, nil)

          case (not is_nil(current_user_id) and creator_id == current_user_id) or
                 pointer_permitted?(objects || first_object,
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
        )
  end

  def can?(_subject, _verbs, object, _opts)
      when is_nil(object) or object in @skip_object_placeholders do
    debug(object, "no object or boundary data")
    nil
  end

  def can?(subject, verbs, :instance, _opts) do
    current_account = current_account(subject)

    Bonfire.Common.Utils.maybe_apply(Bonfire.Me.Accounts, :is_admin?, [current_account],
      fallback_return: nil
    ) ||
      (
        current_user = current_user(subject)
        # cache needed for eg. for extension page
        key = "can:#{id(current_user)}:#{inspect(verbs)}:instance"

        # TODO: use Cachex? but then would need to handle cache invalidation
        with :not_set <- ProcessTree.get(key, default: :not_set) |> debug("from cache?") do
          do_can_instance(current_user, verbs, key)
        end
      )
  end

  def can?(_subject, _verbs, object, _opts) do
    warn(object, "no object or boundary data")
    nil
  end

  def can!(subject, verbs, object, opts \\ []) do
    can?(subject, verbs, object, opts) ||
      raise(Bonfire.Fail.Auth, :not_permitted)
  end

  defp do_can_instance(%{shared_user: %{id: _}} = _subject, _verbs, _key) do
    debug("do not share instance-wide permission on SharedUser")
    false
  end

  defp do_can_instance(subject, verbs, key) do
    val =
      can?(subject, verbs, Bonfire.Boundaries.Scaffold.Instance.instance_acl())
      |> debug("put in cache")

    Process.put(key, val)
    val
  end

  @doc """
  Checks if a pointer has permission based on the specified options.

  ## Examples

      iex> Bonfire.Boundaries.pointer_permitted?(%{id: 1}, verbs: [:edit], current_user: %{id: 2})
      true
  """
  def pointer_permitted?(item, opts) do
    case uids(item) do
      ids when is_list(ids) and ids != [] ->
        load_query(ids, true, opts ++ [limit: 1])
        |> repo().exists?()

      _ ->
        error(
          item,
          "Expected an object or ULID ID, could not check boundaries"
        )

        nil
    end
  end

  @doc """
  Loads a pointer based on the permissions which are checked based on provided options.

  ## Examples

      iex> Bonfire.Boundaries.load_pointer(%{id: 1}, verbs: [:read], current_user: %{id: 2})
      %Needle.Pointer{id: 1}
  """
  def load_pointer(item, opts) do
    case uids(item) do
      ids when is_list(ids) and ids != [] ->
        load_query(ids, e(opts, :ids_only, nil), opts ++ [limit: 1])
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
  Loads pointers based on boundaries (which are checked based on provided options) and returns a list of permitted pointers.

  ## Examples

      iex> Bonfire.Boundaries.load_pointers([%{id: 1}], verbs: [:read], current_user: %{id: 2})
      [%Needle.Pointer{id: 1}]
  """
  def load_pointers(items, opts) do
    # debug(items, "items")
    case uids(items) do
      [] ->
        []

      nil ->
        []

      ids ->
        load_query(ids, e(opts, :ids_only, nil), opts)
        |> repo().many()
    end
  end

  @doc """
  Loads pointers based on boundaries (which are checked based on provided options) and raises an error if not all pointers are permitted.
  """
  def load_pointers!(items, opts) do
    pointers = load_pointers(items, opts)

    if Enum.count(pointers) == Enum.count(items) do
      # TODO: actually compare IDs?
      pointers
    else
      raise(Bonfire.Fail.Auth, :not_permitted)
    end
  end

  defp load_query(ids, true, opts) do
    load_query(ids, nil, opts)
    |> select([main], [:id])
  end

  defp load_query(ids, _, opts) do
    (opts[:from] || Needle.Pointers.query_base(if opts[:include_deleted], do: :include_deleted))
    |> where([p], p.id in ^List.wrap(ids))
    |> boundarise(main_object.id, opts)
  end

  @doc """
  Finds caretaker stereotypes based on the specified caretaker and stereotype IDs.

  ## Examples

      iex> Bonfire.Boundaries.find_caretaker_stereotypes(%User{id: 1}, [%{id: 2}])
      [%Needle.Pointer{id: 1}]
  """
  def find_caretaker_stereotypes(caretaker, stereotypes, from \\ Pointer) do
    find_caretaker_stereotypes_q(caretaker, stereotypes, from)
    |> repo().all()
    |> debug("user stereotypes")
  end

  @doc """
  Finds a caretaker stereotype based on the specified caretaker and stereotype IDs.
  """
  def find_caretaker_stereotype(caretaker, stereotype, from \\ Pointer) do
    find_caretaker_stereotypes_q(caretaker, stereotype, from)
    |> repo().one()
    |> debug("user stereotype")
  end

  @doc """
  Query for caretaker stereotypes based on the specified caretaker and stereotype IDs.
  """
  defp find_caretaker_stereotypes_q(caretaker, stereotypes, from) do
    from(a in from,
      join: c in Caretaker,
      on: a.id == c.id and c.caretaker_id == ^uid!(caretaker),
      join: s in Stereotyped,
      on: a.id == s.id and s.stereotype_id in ^uids(stereotypes),
      preload: [caretaker: c, stereotyped: s]
    )
    |> debug("stereotype query")
  end

  @doc """
  Returns a list of built-in and stereotyped circle structs for the subject that have permission for the given verb(s) on the object.

  ## Options

    * `:include_circles` - restrict which built-in circles to check (list of atoms, defaults to all)
    * `:return` - set to `:names` to return a list of circle slugs/atoms (e.g. `:followers`, `:public`), or `:structs` to return Circle structs, or `:ids` to just return circles IDs (default)

  ## Examples

      iex> list_user_circles_who_can(subject, [:read], object)
      [%Circle{id: ...}, ...]

      iex> list_user_circles_who_can(subject, [:read], object, include_circles: [:followers, :public], return: :names)
      [:followers]
  """
  def list_user_circles_who_can(user, verbs, object, opts \\ []) do
    circles =
      Circles.list_user_built_ins(user, opts)
      |> debug("circles to check")
      |> filter_circles_who_can(verbs, object, opts)
  end

  def filter_circles_who_can(circles, verbs, object, opts \\ []) do
    circle_ids = ids(circles)

    verb_ids =
      List.wrap(verbs)
      |> Enum.map(&Verbs.get_id!/1)
      |> debug("verbs to check")

    permitted_ids =
      Bonfire.Boundaries.Queries.permitted_subjects(circle_ids, verb_ids, uid!(object))
      |> debug("query")
      |> repo().all()
      |> debug("permitted_ids")

    case opts[:return] do
      :names ->
        Enum.filter(circles, fn circle -> circle.id in permitted_ids end)
        |> Circles.get_slugs()

      :structs ->
        Enum.filter(circles, fn circle -> circle.id in permitted_ids end)

      _ids ->
        permitted_ids
    end
    |> debug("permitted_circles")
  end
end
