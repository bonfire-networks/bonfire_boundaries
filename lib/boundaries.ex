defmodule Bonfire.Boundaries do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration

  # alias Bonfire.Data.Identity.User
  alias Bonfire.Boundaries.Circles
  # alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.Identity.Caretaker
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
    Controlleds.has_any_acl?(object, Bonfire.Boundaries.Acls.remote_public_acl_ids())
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

  @doc """
  The boundary each of these objects has for the viewer, as a map of object id to `%{id: object_id, object_id: object_id, verbs: verbs, preset: preset}`, so templates can ask `can?/3` without a query each.

  - `verbs`: what the viewer may do (`Queries.granted_verbs_on/2`, a guest's included), so `can?/3` answers in memory. A boundary built elsewhere with `verbs: nil` is asked about as the object it names, by its `id`
  - `preset`: the object's preset ACL, which names its boundary ("Public", "Local"…, `Presets.preset_boundary_tuple_from_acl/3`)

  Kept apart rather than merged: a merge made the preset ACL's id the boundary's id, so a boundary with no verbs had `can?/3` ask about the ACL instead of the object. `nil` for an object with neither.
  """
  def boundaries_on_objects(list_of_ids, presets, current_user) do
    object_ids = uids(list_of_ids)

    # a guest's too (`nil` is the guest circle), so every viewer's verbs are loaded. Per object or per ACL as configured, to compare them live
    verbs =
      Queries.granted_verbs_query(current_user, object_ids)
      |> repo().all()
      |> Enum.group_by(fn {object_id, _} -> object_id end, fn {_, verb_id} ->
        Verbs.get!(verb_id).verb
      end)

    presets = presets || %{}

    object_ids
    |> Map.new(fn object_id ->
      {object_id, loaded_boundary(object_id, verbs[object_id], presets[object_id])}
    end)
    |> debug("loaded boundaries")
  end

  defp loaded_boundary(_object_id, nil, nil), do: nil

  defp loaded_boundary(object_id, verbs, preset),
    do: %{
      id: object_id,
      object_id: object_id,
      verbs: Enum.sort(verbs || []),
      preset: preset
    }

  def boundary_on_object(id, current_user) do
    boundary_on_object(id, Controlleds.get_preset_on_object(id), current_user)
  end

  @doc "As `boundaries_on_objects/3`, for one object."
  def boundary_on_object(id, preset \\ nil, current_user) do
    object_id = uid(id)

    boundaries_on_objects([object_id], %{object_id => preset}, current_user)
    |> Map.get(object_id)
  end

  @doc """
  Combines several `users_grants_on/2` entries for ONE object into the permissions the subject actually holds.

  That function groups by `{subject, object, value}`, so one user's permissions on one object arrive as several entries: their own grants plus each locality circle they belong to, with positives and negatives split apart. Negatives win, matching `boundarise/3`'s `bool_and` in SQL rather than inventing a second rule.

  Callers that took `List.first/1`, keyed a map by `object_id`, or matched a one-element list were correct only while the query matched the user's own id alone and could return no more than one entry per object.
  """
  def combine_users_grants_on(entries) do
    {denied, allowed} = Enum.split_with(entries, &(e(&1, :value, nil) == false))

    denied_verbs = Enum.flat_map(denied, &(e(&1, :verbs, []) || []))

    verbs =
      allowed
      |> Enum.flat_map(&(e(&1, :verbs, []) || []))
      |> Enum.uniq()
      |> Enum.reject(&(&1 in denied_verbs))
      |> Enum.sort()

    %{verbs: verbs}
  end

  @doc """
  Lists the grants on a set of objects, by any subject, one entry per `{subject, object, value}` with the verbs it covers.

  For inspecting grants, as `Bonfire.Boundaries.Debug` does, NOT for deciding what someone may do: an entry with `value: false` is a denial, and a grant to a circle is listed under the circle rather than its members. Use `can?/4` for one subject, or `permitted_users/3` for several.

  ## Examples

      iex> Bonfire.Boundaries.list_grants_on([1, 2, 3])
  """
  def list_grants_on(things) do
    Queries.query_grants_on(things)
    |> all_grouped_by_verb()
  end

  @doc """
  As `list_grants_on/1`, narrowed to the entries covering every one of these verbs.

  An entry covering `[:see, :read]` may be a denial of both (`value: false`), so this is not "who may see and read it" either: that is `permitted_users/3`.

  ## Examples

      iex> Bonfire.Boundaries.list_grants_on([1, 2, 3], [:see, :read])
  """
  def list_grants_on(things, verbs) do
    Queries.query_grants_on(things, verbs)
    |> all_grouped_by_verb()
    |> only_with_all_verbs(verbs)
  end

  @doc """
  Which of these users may do every one of these verbs on the object, each as `can?/3` would answer for them alone, in one query whatever their number. Returns those of the given users who may, as given.

  ## Examples

      iex> Bonfire.Boundaries.permitted_users([bob, carol], [:see, :read], post)
      [bob]
  """
  def permitted_users(users, verbs, object) do
    case List.wrap(users) do
      [] ->
        []

      users ->
        permitted =
          Queries.permitted_users(users, verbs, uid!(object))
          |> repo().all()
          |> MapSet.new()

        Enum.filter(users, &MapSet.member?(permitted, uid(&1)))
    end
  end

  @doc """
  Lists the grants that count for these users on a set of objects: their own, and their locality circle's, one entry per `{subject, object, value}`.

  The raw material of a user's permissions rather than the answer: `combine_users_grants_on/1` combines one user's entries into what they hold (as the loaded boundaries `can?/4` reads do), an entry with `value: false` is a denial, and a locality circle's grants are listed under the circle. To decide what someone may do, use `can?/4`, or `permitted_users/3` for several.

  ## Examples

      iex> Bonfire.Boundaries.users_grants_on([%{id: 1}], [%{id: 2}])
  """
  def users_grants_on(users, things) do
    Queries.query_users_grants_on(users, things)
    |> all_grouped_by_verb()
  end

  # Retired 14 October 2026: its callers all asked "which of these users may", which `permitted_users/3` answers in SQL with `can?/3`'s rules. This returned grant ENTRIES instead, one per `{subject, value}`, so each caller had to notice a denial itself (fan-out didn't, and notified people denied the object)
  # @doc """
  # Lists grants for a given set of users on a set of objects, filtered by verbs.
  #
  # ## Examples
  #
  #     iex> Bonfire.Boundaries.users_grants_on([%{id: 1}], [%{id: 2}], [:see, :read])
  #     [%Bonfire.Boundaries.Summary{object_id: 2, subject_id: 1}]
  # """
  # def users_grants_on(users, things, verbs) do
  #   Queries.query_users_grants_on(users, things, verbs)
  #   |> all_grouped_by_verb()
  #   |> only_with_all_verbs(verbs)
  # end

  # The verb FILTER is applied in SQL by `Queries.query_users_grants_on/3`; what remains here is the "holds ALL of them" test, which cannot join it without a subquery, the rows are still needed to build each entry's `:verbs` list.
  defp only_with_all_verbs(entries, verbs) do
    verb_names =
      List.wrap(verbs)
      |> Enum.map(fn
        slug when is_atom(slug) -> Verbs.get_id!(slug)
        id when is_binary(id) or is_map(id) -> uid(id)
      end)
      |> Enum.map(&Verbs.get(&1).verb)
      |> Enum.sort()

    Enum.filter(entries, &(&1.verbs == verb_names))
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
           # either creator shape depending on the object type — pruned per schema
           |> repo().maybe_preload([:creator, created: [:creator]], prune: true),
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
  Optimistic permission check for use in feed action button templates that may
  render before `object_boundary` has been preloaded by `update_many` as
  `%{object_id: ..., verbs: ...}` (`boundaries_on_objects/3`).

  Returns `true` (so the button stays enabled) when:
    * `object_boundary` is `nil` or `:skip_boundary_preload` — defer to server-side
      validation when the action is performed
    * there is no current user — guest users see enabled buttons that prompt login
      on click (consistent with the existing boost/like/reply UX)

  Otherwise delegates to `can?/3` against the preloaded boundary, which runs
  in-memory (no DB query) when the viewer's verbs are loaded.

  Use this instead of `can?/3` in any per-activity template to avoid n+1
  permission queries when the surrounding preload chain didn't finish.
  """
  def can_or_unloaded?(context, verb, object_boundary) do
    is_nil(current_user_id(context)) or
      object_boundary in [nil, :skip_boundary_preload] or
      can?(context, verb, object_boundary)
  end

  @doc """
  Like `can?/4`, but for an action that ALSO requires federation to reach the target (follow,
  reply, like, boost, DM, mention). The subject must have the boundary permission AND — when the
  target is remote — federation must be possible given the current mode (open / allowlist-only /
  manual / disabled). The federation subject is `opts[:target_user]` if given, else `object` or its creator (a
  post boundary often can't carry the author, so callers pass `target_user:` for those). Degrades to plain `can?`
  when the federate extension is disabled.
  """
  def can_interact?(subject, verb, object, opts \\ []) do
    can?(subject, verb, object, opts) and
      federated_interaction_allowed?(subject, opts[:target_user] || object, opts)
  end

  @doc "Optimistic (template) variant of `can_interact?/4`, mirroring `can_or_unloaded?/3`."
  def can_interact_or_unloaded?(subject, verb, object_boundary, opts \\ []),
    do: is_nil(interaction_refusal(subject, verb, object_boundary, opts))

  @doc """
  Why `can_interact_or_unloaded?/4` refuses, so a disabled button can say: `nil` when it doesn't, `:boundary` when the object's boundary does, `:federation` when the target is remote and federation can't reach it from here (off, paused, or not allowlisted).
  """
  def interaction_refusal(subject, verb, object_boundary, opts \\ []) do
    cond do
      can_or_unloaded?(subject, verb, object_boundary) != true ->
        :boundary

      # no resolvable target → stay optimistic (the server-side `can_interact?` is the real gate)
      (opts[:target_user] || object_boundary) in [nil, :skip_boundary_preload] ->
        nil

      federated_interaction_allowed?(subject, opts[:target_user] || object_boundary, opts) != true ->
        :federation

      true ->
        nil
    end
  end

  defp federated_interaction_allowed?(subject, target, opts) do
    # the boundary `can?` above already enforced blocks → skip the redundant block query
    maybe_apply(
      Bonfire.Federate.ActivityPub,
      :interaction_allowed?,
      [subject, target, Keyword.put(opts, :skip_block_check, true)],
      fallback_return: true
    )
  end

  @doc """
  Checks if a subject has permission to conduct the specified action(s)/verb(s) on an object.

  A list means ALL of them: every verb, on every object. `{:any, list}` in place of the verbs or the objects means at least one. Several subjects in a plain list are pooled, as one person's grants and circles are; `{:any, subjects}` (each on their own) is not supported yet, and `permitted_users/3` answers which of several users may.

  ## Examples

      iex> Bonfire.Boundaries.can?(%User{id: 1}, [:see], %{id: 2})
      false

      iex> Bonfire.Boundaries.can?(moderator, {:any, [:grant, :mediate]}, post)
      true
  """
  def can?(subject, verbs, object, opts \\ [])

  def can?({:any, _subjects}, _verbs, _object, _opts),
    do:
      raise(
        "Asking whether any of several subjects may is not supported yet: `permitted_users/3` says which of them may"
      )

  # just for typos ;)
  def can?(subject, can_verbs?, :instance_wide, opts),
    do: can?(subject, can_verbs?, :instance, opts)

  # a loaded boundary (`boundaries_on_objects/3`) with the viewer's verbs loaded; without (`verbs: nil`) it is asked about as the object it names, by its `id`
  def can?(subject, can_verbs?, %{object_id: _, verbs: can_verbs!} = object_boundary, opts)
      when is_list(can_verbs!) do
    debug(object_boundary, " preloaded object_boundary")

    skip? = Queries.skip_boundary_check?(opts)

    # the loaded boundary's verbs are those granted and not denied (`combine_users_grants_on/1`), so holding one is being permitted it
    skip? == true ||
      (skip? == :admins and
         Bonfire.Common.Utils.maybe_apply(Bonfire.Me.Accounts, :is_admin?, [subject],
           fallback_return: nil
         )) ||
      holds_verbs?(can_verbs!, can_verbs?)
  end

  def can?(circle_name, verbs, object, opts) when is_atom(circle_name) do
    # lookup if a built-in circle (eg. local users) has permission (note that some circle members may NOT have permission if they're also in another circle with negative permissions)
    can?([current_user: Circles.get_id(circle_name)], verbs, object, opts)
  end

  def can?(subject, verbs, {:any, objects}, opts) when is_list(objects),
    do: can_on_objects?(:any, subject, verbs, objects, opts)

  def can?(subject, verbs, object, opts)
      when is_map(object) or is_binary(object) or is_list(object),
      do: can_on_objects?(:all, subject, verbs, List.wrap(object), opts)

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

  defp holds_verbs?(held, {:any, verbs}), do: Enum.any?(List.wrap(verbs), &holds_verb?(held, &1))
  defp holds_verbs?(held, verbs), do: Enum.all?(List.wrap(verbs), &holds_verb?(held, &1))
  defp holds_verb?(held, verb), do: Enum.member?(held, Verbs.get(verb)[:verb])

  # `mode` is `:all` (every object) or `:any` (at least one). What the subject created needs no check
  defp can_on_objects?(mode, subject, verbs, objects, opts) do
    skip? =
      Queries.skip_boundary_check?(opts)
      |> debug("check object?")

    skip? == true ||
      (skip? == :admins and
         Bonfire.Common.Utils.maybe_apply(Bonfire.Me.Accounts, :is_admin?, [subject],
           fallback_return: nil
         )) ||
      (
        # `current_user_or_id` so a bare subject id (eg. the circle-as-subject clause above) is honored instead of silently downgrading the check to guest
        current_user = current_user_or_id(subject)
        objects = Enum.reject(objects, fn o -> is_nil(o) or o in @skip_object_placeholders end)
        to_check = Enum.reject(objects, &created_by?(&1, id(current_user)))

        cond do
          objects == [] -> false
          to_check == [] -> true
          mode == :any and to_check != objects -> true
          true -> permitted_objects?(mode, to_check, current_user, subject, verbs, opts)
        end
      )
  end

  # TODO: include caretaker
  defp created_by?(_object, nil), do: false

  defp created_by?(object, user_id) when is_map(object),
    do:
      (e(object, :created, :creator_id, nil) || e(object, :created, :creator, :id, nil) ||
         e(object, :creator_id, nil) || e(object, :creator, :id, nil)) == user_id

  defp created_by?(_object, _user_id), do: false

  # the caller's options reach the query (eg. `include_deleted`: soft-deleted objects are left out unless asked for, as when restoring an archived group, and asking keeps their boundaries in force), with the subject and verbs resolved here taking precedence
  defp permitted_objects?(mode, objects, current_user, subject, verbs, opts) do
    # without the caller's own `verb`/`verbs`: a singular `verb:` overrides `verbs:` in the query, so eg. a delete epic's `verb: :delete` turned "may the activity_pub circle read this user" into "may it delete them", refusing the group's federated `Delete`
    opts =
      opts
      |> Keyword.drop([:verb, :verbs])
      |> Keyword.merge(
        current_user: current_user,
        current_account: current_account(subject),
        verbs: verbs
      )

    case {mode, uids(objects) |> Enum.uniq()} do
      {_, []} ->
        false

      {:any, ids} ->
        pointer_permitted?(ids, opts) == true

      # every one of them loads for the subject, rather than the first that does
      {:all, ids} ->
        load_query(ids, true, opts) |> repo().all() |> length() == length(ids)
    end
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
    # one object is OPENED, so checked for `:read` unless the caller asks otherwise (`load_pointers/2` lists, so takes the listing default)
    opts = opts |> to_options() |> Keyword.put_new(:verbs, [:read])

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
    # scheduled objects are included unless `exclude_scheduled`: built-in boundaries such as the instance ACL have fixed ids that read as future dates, so the scheduled-content filter dropped them, and `can?(_, _, :instance)` was false for all but admins
    (opts[:from] ||
       Bonfire.Common.Needles.query_base(
         deleted: opts[:include_deleted],
         include_scheduled: !opts[:exclude_scheduled]
       ))
    # (opts[:from] ||
    #    Bonfire.Common.Needles.query_base(if opts[:include_deleted], do: :include_deleted))
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
