defmodule Bonfire.Boundaries.Blocks do
  @moduledoc """
  Handles blocking of users and instances

  This module provides functions to block and unblock users or instances, check
  if a user or instance is blocked, and manage block lists. It also includes
  federation support for ActivityPub.
  """

  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Grants
  # alias Bonfire.Data.Identity.User
  # alias Bonfire.Data.AccessControl.Grant
  # alias Bonfire.Data.Identity.Caretaker

  @behaviour Bonfire.Federate.ActivityPub.FederationModules
  def federation_module,
    do: [
      "Block",
      # a moderator closing a thread to further replies, which is a `:lock` block on the object
      "Lock",
      {"Undo", "Lock"}
    ]

  @doc """
  Converts provided block types (eg. `:ghost` or `:silence`) into a list of internal block types.

  ## Examples

      iex> Bonfire.Boundaries.Blocks.types_blocked([:ghost, :silence])
      [:ghost_them, :silence_them]

      iex> Bonfire.Boundaries.Blocks.types_blocked(:ghost)
      [:ghost_them]

      iex> Bonfire.Boundaries.Blocks.types_blocked(nil)
      [:silence_them, :ghost_them]
  """
  def types_blocked(types) when is_list(types) do
    Enum.flat_map(types, &types_blocked/1) |> Enum.uniq()
  end

  def types_blocked(type) when type in [:ghost, :ghost_them] do
    [:ghost_them]
  end

  def types_blocked(type) when type in [:silence, :silence_them] do
    [:silence_them]
  end

  def types_blocked(:hide) do
    [:silence_them]
  end

  def types_blocked(_) do
    [:silence_them, :ghost_them]
  end

  @doc """
  Blocks a user or instance for everyone on the instance (for admin/mod use only).

  ## Examples

      iex> Bonfire.Boundaries.Blocks.instance_wide_block(user, :ghost)
      {:ok, "Blocked"}
  """
  def instance_wide_block(user_or_instance_to_block, block_type \\ nil) do
    block(user_or_instance_to_block, block_type, :instance_wide)
  end

  @doc """
  Blocks a remote instance.

  ## Block for current user

      iex> Bonfire.Boundaries.Blocks.remote_instance_block("example.com", :silence, current_user)
      {:ok, "Blocked"}

  ## Block for everyone on the instance (as an admin/mod)

      iex> Bonfire.Boundaries.Blocks.remote_instance_block("example.com", :silence, :instance_wide)
      {:ok, "Blocked"}
  """

  # def remote_instance_block(display_hostname, block_type, scope) do
  #   with {:ok, circle} <- Bonfire.Boundaries.Circles.get_or_create(display_hostname, Bonfire.Boundaries.Scaffold.Instance.activity_pub_circle()) do
  #     debug(circle, "blocking (#{block_type}) an entire instance: #{display_hostname}")
  #     block(circle, block_type, scope)
  #   end
  # end

  @doc """
  Blocks, silences, or ghosts a user or instance.

  ## Block a user for current user

      iex> Bonfire.Boundaries.Blocks.block(user, current_user: blocker)
      {:ok, "Blocked"}

  ## Block a user for everyone on the instance (as an admin/mod)

      iex> Bonfire.Boundaries.Blocks.block(user, :instance_wide)
      {:ok, "Blocked"}

  ## Silence a user for current user

      iex> Bonfire.Boundaries.Blocks.block(user, :silence, current_user: blocker)
      {:ok, "Blocked"}

  ## Silence a user for everyone on the instance (as an admin/mod)

      iex> Bonfire.Boundaries.Blocks.block(user, :silence, :instance_wide)
      {:ok, "Blocked"}

  ## Ghost a user for current user

      iex> Bonfire.Boundaries.Blocks.block(user, :ghost, current_user: blocker)
      {:ok, "Blocked"}

  ## Ghost a user for everyone on the instance (as an admin/mod)

      iex> Bonfire.Boundaries.Blocks.block(user, :ghost, :instance_wide)
      {:ok, "Blocked"}
  """
  def block(user_or_instance_to_block, block_type \\ nil, scope)

  # just for typos ;)
  def block(user_or_instance, block_type, :instance),
    do: block(user_or_instance, block_type, :instance_wide)

  # def block(
  #       %{__struct__: schema, display_hostname: display_hostname} = _instance_to_block,
  #       block_type,
  #       scope
  #     )
  #     when schema == Bonfire.Data.ActivityPub.Peer do
  #   remote_instance_block(display_hostname, block_type, scope)
  # end

  def block(user_or_instance_id_or_username, block_type, scope)
      when is_binary(user_or_instance_id_or_username) do
    with {:ok, user_or_circle} <-
           Bonfire.Common.Needles.get(user_or_instance_id_or_username, skip_boundary_check: true) do
      debug(user_or_circle, "found by ID or username")
      block(user_or_circle, block_type, scope)
    else
      _ ->
        if Types.is_uid?(user_or_instance_id_or_username) do
          debug("assume it's an instance display_hostname")

          maybe_apply(Bonfire.Federate.ActivityPub.Instances, :get, [
            user_or_instance_id_or_username
          ])
          ~> block(block_type, scope)
        else
          error(user_or_instance_id_or_username, "Could not find what to block")
        end
    end
  end

  def block(user_or_instance_to_block, block_type, scope) do
    types_blocked =
      types_blocked(block_type)

    # |> debug("types_blocked for #{inspect block_type}")

    with {:ok, result} <-
           mutate(
             :block,
             user_or_instance_to_block,
             block_type || List.first(types_blocked),
             scope
           ) do
      # debug(result, "blooocked")

      # Severing follows is OPT-IN, because it can signal the block to the blocked person. Unfollowing when silencing would drop their follower count (and leaving removes us from their followers list). `unblock/3` does not restore the follow either, so what it costs is permanent.
      # UI may well want provide a "mute and unfollow", so it stays available, they just have to ask for it rather than have it happen unannounced.
      if e(scope, :also_unfollow, false) and user_or_instance_to_block != :instance_wide and
           scope != :instance_wide do
        me = Utils.current_user_required!(scope)

        if :ghost_them in types_blocked do
          debug("make the person I am ghosting unfollow me - TODO: do not federate this?")

          Utils.maybe_apply(Bonfire.Social.Graph.Follows, :unfollow, [
            user_or_instance_to_block,
            me
          ])
        end

        if :silence_them in types_blocked do
          debug("unfollow the person I am silencing")

          Utils.maybe_apply(Bonfire.Social.Graph.Follows, :unfollow, [
            me,
            user_or_instance_to_block
          ])
        end
      end

      {:ok, result}
    end
  end

  @doc """
  Unblocks a user or instance.

  ## Examples

      iex> Bonfire.Boundaries.Blocks.unblock(user, :ghost, current_user: unblocker)
      {:ok, "Unblocked"}

      iex> Bonfire.Boundaries.Blocks.unblock(user, :silence, :instance_wide)
      {:ok, "Unblocked"}
  """
  def unblock(user_or_instance_to_unblock, block_type \\ nil, scope) do
    mutate(:unblock, user_or_instance_to_unblock, block_type, scope)
  end

  @doc """
  Closes an object to further participation: a moderator locking a thread, or a group being archived.

  A named wrapper over `block/3`, so call sites say what they mean rather than passing a `:lock` atom, and so there is ONE seam to hang outgoing federation on when it lands — no block of any kind federates today.

  ## Examples

      iex> Bonfire.Boundaries.Blocks.lock(post, current_user: moderator)
  """
  def lock(object, scope) do
    with {:ok, _} = ok <- block(object, :lock, scope) do
      maybe_federate_lock(:lock, object, scope)
      ok
    end
  end

  @doc "Reopens an object closed by `lock/2`."
  def unlock(object, scope) do
    with {:ok, _} = ok <- unblock(object, :lock, scope) do
      maybe_federate_lock(:unlock, object, scope)
      ok
    end
  end

  # A closed THREAD is worth telling other instances about, and our own ingest already accepts it (`ap_receive_activity/3` below). A closed ACTOR is not: `Lock` is per-post everywhere it is implemented, so `Lock{Group}` would be a shape with no receiver — an archived group says `postingRestrictedToMods` on its actor instead, which is why this skips characters.
  # Routed explicitly at THIS module because outgoing publishing dispatches on `{verb, object_type}` and falls back to the object's own context module, which for a post is `Bonfire.Posts` — the same `federation_module:` override `Bonfire.Social.Quotes` uses for its requests.
  # Never fatal: failing to announce a lock must not undo the lock.
  @doc """
  Publishes a thread closing or reopening as `Lock` / `Undo{Lock}`.

  Reached through the `federation_module: __MODULE__` override rather than by type dispatch, since the object being locked is a post, whose own context module would otherwise be asked to publish a verb it knows nothing about.

  ⚠️ The moderator's REASON has nowhere to come from yet: an incoming lock carries it in `summary` and we store it (`maybe_store_moderation_reason/2`), but a local lock creates grants rather than a record, so there is nothing to read back. Emitted without one until that is decided.
  """
  def ap_publish_activity(subject, verb, object) when verb in [:lock, :unlock] do
    with {:ok, actor} <- ActivityPub.Actor.get_cached(pointer: subject),
         {:ok, ap_object} <- ActivityPub.Object.get_cached(pointer: object) do
      # no `pointer:` — a lock creates GRANTS rather than a record, so the activity has no local pointable of its own, and claiming the locked object's would collide with the AP object already holding it
      params = %{actor: actor, object: ap_object}

      case verb do
        :lock -> ActivityPub.lock(params)
        :unlock -> ActivityPub.unlock(params)
      end
    else
      e -> error(e, "Could not find the actor or object to #{verb}")
    end
  end

  defp maybe_federate_lock(verb, object_or_id, scope) do
    # callers pass an id as readily as a struct (the locking LiveView handler passes one), and the locality check below deliberately RAISES rather than guessing when `:peered` is not loaded — so load it here, mirroring what `AdapterUtils.preload_peered/1` asks of an object
    object =
      case object_or_id do
        id when is_binary(id) ->
          case Bonfire.Common.Needles.get(id, skip_boundary_check: true) do
            {:ok, object} -> object
            _ -> nil
          end

        object ->
          object
      end
      |> repo().maybe_preload([:peered, created: [creator: :peered]], prune: true)

    character_schemas =
      Bonfire.Common.Config.get(:types_character_schemas, [], :bonfire)

    # and only for objects WE host: applying an incoming `Lock` goes through this same function (`ap_receive_activity/3` below, and `Threads.ap_receive_comments_enabled/4` for the `commentsEnabled` form), so announcing a remote object's lock would echo the origin's own decision back at the fediverse as though it were ours
    if Types.object_type(object) not in character_schemas and
         Utils.maybe_apply(Bonfire.Federate.ActivityPub.AdapterUtils, :is_local?, [object],
           fallback_return: false
         ) == true do
      try do
        Utils.maybe_apply(
          Bonfire.Federate.ActivityPub.Outgoing,
          :maybe_federate,
          [current_user(scope), verb, object, [federation_module: __MODULE__]],
          fallback_return: nil
        )
      rescue
        e -> error(e, "Could not federate the #{verb}")
      catch
        :exit, e -> error(e, "Could not federate the #{verb}")
      end
    end
  end

  @doc """
  Unblocks *all* users or instances for a given block type and scope (only used for debugging purposes)

  ## Examples

      iex> Bonfire.Boundaries.Blocks.unblock_all(:ghost, :instance_wide)
      {:ok, "All unblocked"}
  """
  def unblock_all(block_type \\ nil, scope)

  def unblock_all(block_type, :instance_wide) do
    instance_wide_circles(block_type)
    |> Circles.empty_circles()
  end

  def unblock_all(block_type, scope) do
    user_block_circles(current_user(scope), block_type)
    |> Circles.empty_circles()
  end

  # just for typos ;)
  defp mutate(block_or_unblock, user_or_instance_to_block_or_unblock, block_type, :instance),
    do: mutate(block_or_unblock, user_or_instance_to_block_or_unblock, block_type, :instance_wide)

  defp mutate(:block, object_to_hide, :hide, scope) do
    current_user = current_user(scope)
    acl = Acls.get_or_create_object_custom_acl(object_to_hide, current_user || scope)

    who_to_hide_it_from =
      if scope == :instance_wide do
        # hiding instance-wide means we hide for these circles
        instance_wide_circles([:guest, :local, :activity_pub])
      else
        current_user
      end

    granted =
      Grants.grant_role(who_to_hide_it_from, acl, :cannot_discover,
        current_user: current_user,
        scope: scope
      )

    # |> debug("done")

    if Enums.all_ok?(granted) do
      {:ok, l("Hidden")}
    else
      error(granted, l("Could not hide it"))
    end
  end

  defp mutate(:unblock, object_to_hide, :hide, scope) do
    # Reverse of the `:hide` block above: remove the `:cannot_discover` grants
    # we added to the object's custom ACL for the relevant circle(s).
    current_user = current_user(scope)
    acl = Acls.get_or_create_object_custom_acl(object_to_hide, current_user || scope)

    who_to_unhide_for =
      if scope == :instance_wide do
        instance_wide_circles([:guest, :local, :activity_pub])
      else
        current_user
      end

    removed =
      Grants.remove_role(who_to_unhide_for, acl, :cannot_discover,
        current_user: current_user,
        scope: scope
      )

    if Enums.all_ok?(removed) do
      {:ok, l("Unhidden")}
    else
      error(removed, l("Could not unhide it"))
    end
  end

  defp mutate(:block, object_to_lock, :lock, scope) do
    current_user = current_user(scope)
    acl = Acls.get_or_create_object_custom_acl(object_to_lock, current_user || scope)

    # if scope == ? do
    #   # TODO: lock for specific circles
    # else
    # locking for all means these circles
    # FIXME: should we optimise by simply applying a preset ACL?
    who_to_lock =
      instance_wide_circles([:guest, :local, :activity_pub])

    # end

    granted =
      Grants.grant_role(who_to_lock, acl, :cannot_participate,
        current_user: current_user,
        scope: scope
      )

    # |> debug("locks granted")

    if Enums.all_ok?(granted) do
      {:ok, l("Locked")}
    else
      error(granted, l("Could not lock it"))
    end
  end

  defp mutate(:unblock, object_to_unlock, :lock, scope) do
    current_user = current_user(scope)
    acl = Acls.get_or_create_object_custom_acl(object_to_unlock, current_user || scope)

    # if scope == ? do
    #   # TODO: lock for specific circles
    # else
    # locking for all means these circles
    # FIXME: should we optimise by simply applying a preset ACL?
    who_to_unlock =
      instance_wide_circles([:guest, :local, :activity_pub])

    # end

    granted =
      Grants.remove_role(who_to_unlock, acl, :cannot_participate,
        current_user: current_user,
        scope: scope
      )

    # |> debug("done")

    if Enums.all_ok?(granted) do
      {:ok, l("Unlocked")}
    else
      error(granted, l("Could not unlock it"))
    end
  end

  # a `nil`/`:any`/`:block` block type means "all block types": delegate to the per-type paths so the `:silence` clauses (which also maintain the `:silence_me` reverse-index that boundary queries filter on) are used. The generic clauses below only touch `:silence_them`/`:ghost_them`, so a plain `block/2`/`unblock/2` (nil type) or `block(x, :block, scope)` would otherwise leave `:silence_me` dangling (and a later per-type `unblock(x, :silence, scope)` would fail finding nothing to remove there). Works for both per-user and instance-wide scopes (each delegated type re-dispatches to its own clause).
  defp mutate(block_or_unblock, user_or_instance_to_block, block_type, scope)
       when block_type in [nil, :any, :block] do
    # succeed if either type changed something (one side may legitimately have nothing to do),
    # returning a flat `{:ok, _}`/`{:error, _}` like the sibling clauses
    [:ghost, :silence]
    |> Enum.map(&mutate(block_or_unblock, user_or_instance_to_block, &1, scope))
    |> Enums.first_ok_or_error()
  end

  defp mutate(
         block_or_unblock,
         user_or_instance_to_block,
         block_type,
         :instance_wide
       )
       when block_type in [:silence, :silence_them] do
    debug(
      "add silence block to both instance's :silence_them and the other to user_or_instance_to_block's :silence_me"
    )

    # instance list of people/instances silenced
    with {:ok, _ret} <-
           types_blocked(block_type)
           |> instance_wide_circles()
           |> info("instance_wide_circles_silenced1")
           |> do_mutate_blocklists(block_or_unblock, user_or_instance_to_block, ...),
         # that user or instance's list of people who silenced them (this list isn't meant to be visible to them, but is used so queries can filter stuff using `Bonfire.Boundaries.Queries`)
         #  [:silence_me]
         {:ok, ret} <-
           [:guest, :local]
           |> instance_wide_circles()
           |> info("instance_wide_circles_silenced2")
           |> do_mutate_blocklists(
             block_or_unblock,
             ...,
             per_user_circles(
               user_or_instance_to_block,
               [:silence_me],
               block_or_unblock == :block
             )
           ) do
      {:ok, ret}
    end
  end

  defp mutate(
         block_or_unblock,
         user_or_instance_to_block,
         block_type,
         :instance_wide
       ) do
    instance_wide_circles(types_blocked(block_type))
    |> info("instance_wide_circles_blocked")
    |> do_mutate_blocklists(block_or_unblock, user_or_instance_to_block, ...)
  end

  # @doc "Block something for the current user (current_user should be passed as scope)"
  defp mutate(block_or_unblock, user_or_instance_to_block, block_type, scope)
       when block_type in [:silence, :silence_them] do
    current_user = Utils.current_user_required!(scope)

    debug(
      "add silence block to both users' circles, one to current_user's :silence_them and the other to user_or_instance_to_block's :silence_me"
    )

    # my list of people/instances I've silenced
    with {:ok, _ret} <-
           mutate_blocklists(
             block_or_unblock,
             user_or_instance_to_block,
             types_blocked(block_type),
             current_user
           ),
         # their list of people who silenced them (this list isn't meant to be visible to them, but is used so queries can filter stuff using `Bonfire.Boundaries.Queries`)
         {:ok, ret} <-
           mutate_blocklists(
             block_or_unblock,
             current_user,
             [:silence_me],
             user_or_instance_to_block
           ) do
      {:ok, ret}
    end
  end

  defp mutate(block_or_unblock, user_or_instance_to_block, block_type, opts) do
    mutate_blocklists(
      block_or_unblock,
      user_or_instance_to_block,
      types_blocked(block_type),
      Utils.current_user(opts)
    )
  end

  defp mutate_blocklists(
         block_or_unblock,
         user_or_instance_add,
         block_type,
         circle_caretaker
       ) do
    case per_user_circles(circle_caretaker, block_type, block_or_unblock == :block) do
      [] ->
        error(circle_caretaker, "This user has no circles for block type #{inspect(block_type)}")

      circles ->
        circles
        |> debug("user circles to block for #{inspect(block_type)}")
        |> repo().maybe_preload(caretaker: [caretaker: [:profile]])
        |> do_mutate_blocklists(block_or_unblock, user_or_instance_add, ...)
    end
  end

  defp do_mutate_blocklists(
         block_or_unblock,
         %{__struct__: schema, display_hostname: display_hostname} = instance_to_block,
         circles
       )
       when schema == Bonfire.Data.ActivityPub.Peer do
    debug("for blocking of instances, we use the instance's Circle instead of the Peer")

    with {:ok, circle_to_block} <-
           Bonfire.Boundaries.Circles.get_or_create(
             display_hostname,
             Bonfire.Boundaries.Scaffold.Instance.activity_pub_circle()
           ) do
      debug(circle_to_block, "#{block_or_unblock} an entire instance: #{display_hostname}")

      do_mutate_blocklists(
        block_or_unblock,
        circle_to_block,
        circles
      )
    end
  end

  defp do_mutate_blocklists(:block, user_or_instance_to_block, circles) do
    # TODO: properly validate the inserts
    with done when is_list(done) <-
           Circles.add_to_circles(user_or_instance_to_block, circles) do
      {:ok, "Blocked"}
    else
      e ->
        error(e)
        {:error, "Could not block"}
    end
  end

  defp do_mutate_blocklists(:unblock, user_or_instance_to_unblock, circles) do
    with {deleted, _} when deleted > 0 <-
           Circles.remove_from_circles(user_or_instance_to_unblock, circles) do
      {:ok, "Unblocked"}
    else
      e ->
        warn(e, "Could not unblock")
        {:error, "Could not unblock"}
    end
  end

  @doc """
  Checks if a user or instance is blocked.

  ## Examples

      iex> Bonfire.Boundaries.Blocks.is_blocked?(instance, :ghost, current_user: checker)
      false

      iex> Bonfire.Boundaries.Blocks.is_blocked?(user, :silence, :instance_wide)
      true
  """
  def is_blocked?(user_or_instance, block_type \\ :any, opts \\ [])

  # just for typos ;)
  def is_blocked?(user_or_instance, block_type, :instance),
    do: is_blocked?(user_or_instance, block_type, :instance_wide)

  def is_blocked?(user_or_instance, block_type, :instance_wide)
      when not is_nil(user_or_instance) do
    instance_wide_circles(types_blocked(block_type))
    # |> debug("instance_wide_circles_blocked")
    |> Bonfire.Boundaries.Circles.is_encircled_by?(user_or_instance, ...)
  end

  def is_blocked?(user_or_instance, block_type, opts) when not is_nil(user_or_instance) do
    is_blocked?(user_or_instance, block_type, :instance_wide) ||
      is_blocked_by?(
        user_or_instance,
        block_type,
        debug(
          e(opts, :user_ids, nil) || current_user(opts),
          "check if blocked #{inspect(block_type)} per-user, if any has/have been provided in opts"
        )
      )
  end

  def is_blocked?(_user_or_instance, _block_type, _opts) do
    warn("no object provided to check")
    false
  end

  @doc """
  Lists blocked users or instances for a given block type and scope

  ## Examples

      iex> Bonfire.Boundaries.Blocks.list(:ghost, :instance_wide)
      [%{id: "123", type: :ghost}, %{id: "456", type: :ghost}]

      iex> Bonfire.Boundaries.Blocks.list(:silence, current_user: user)
      [%{id: "789", type: :silence}]
  """
  @doc "Counts subjects in instance-wide block circles."
  def count_blocked(:instance_wide, block_type \\ :any) do
    import Ecto.Query

    circle_ids = instance_wide_circles(types_blocked(block_type))

    from(enc in Bonfire.Data.AccessControl.Encircle,
      where: enc.circle_id in ^circle_ids,
      select: count(enc.id)
    )
    |> repo().one() || 0
  end

  def list(block_type, :instance_wide) do
    instance_wide_circles(types_blocked(block_type))
    |> Bonfire.Boundaries.Circles.list_by_ids()
    |> repo().maybe_preload(
      caretaker: [:profile],
      encircles: [:peer, subject: [:profile, :character]]
    )
  end

  def list(block_type, opts) do
    per_user_circles(current_user(opts), types_blocked(block_type))
    |> repo().maybe_preload(encircles: [:peer, subject: [:profile, :character]])
  end

  ###

  def instance_wide_circles(block_types) when is_list(block_types) do
    Circles.ids_for_stereotypes(block_types)
  end

  def instance_wide_circles(block_type) do
    types_blocked(block_type)
    |> instance_wide_circles()
  end

  # defp per_user_circles(%{__struct__: schema, display_hostname: display_hostname} = instance_to_block,
  #       block_types
  #     ) when schema == Bonfire.Data.ActivityPub.Peer do
  #       debug(instance_to_block, "instance_to_block with #{inspect block_types}")
  #   raise "Instance silencing not implemented"
  # end
  # `create?` is for the mutating path only, and only in the adding direction.
  #
  # Only users are scaffolded with block circles, but a Category is an actor with a character of its own and can be silenced like anyone else. Silencing keeps a reverse index on the object BEING silenced (`silence_me`, "people who silenced me"), so that object needs the circle, and it gets one the first time somebody silences it. On demand rather than scaffolded, which would be rows on every group and topic ever created to serve the ones nobody ever blocks.
  #
  # The read paths must never create: asking who someone has blocked is not an act that should write. Nor is unblocking, where there is nothing to remove from a circle that was never made.
  defp per_user_circles(current_user, block_types, create? \\ false)

  defp per_user_circles(current_user, block_types, true) do
    case Circles.stereotype_circles_for(current_user, block_types) do
      [] ->
        # The circle alone denies nothing: what makes a block bite is the ACL granting negatively against it, plus that ACL being attached to the actor. So the whole set is created together, and only for the stereotypes THIS block uses.
        # Reached only when the actor has none, which for a user is never, so the usual path is the one lookup below and no writes.
        Bonfire.Boundaries.Scaffold.create_missing_block_boundaries(current_user, block_types)
        Circles.stereotype_circles_for(current_user, block_types)

      circles ->
        circles
    end
  end

  defp per_user_circles(current_user, block_types, _no_create),
    do: Circles.stereotype_circles_for(current_user, block_types)

  defp per_user_circle_ids(current_user, block_types),
    do: Circles.stereotype_circle_ids_for(current_user, block_types)

  def user_block_circles(current_user, block_type) do
    types_blocked(block_type)
    # |> debug()
    |> per_user_circles(current_user, ...)
  end

  defp is_blocked_by?(user_or_peer, block_type, current_user_ids)
       when not is_nil(user_or_peer) and is_list(current_user_ids) and current_user_ids != [] do
    # info(user_or_peer, "user_or_peer to check")
    debug(current_user_ids, "current_user_ids")

    block_types = types_blocked(block_type)

    current_user_ids
    |> debug("user_ids")
    |> Enum.flat_map(&per_user_circle_ids(uid(&1), block_types))
    |> debug("user_block_circle_ids")
    |> Bonfire.Boundaries.Circles.is_encircled_by?(user_or_peer, ...)
  end

  defp is_blocked_by?(user_or_peer, block_type, user_id)
       when not is_nil(user_or_peer) and is_binary(user_id) do
    is_blocked_by?(user_or_peer, block_type, [user_id])
  end

  defp is_blocked_by?(user_or_peer, block_type, %{} = user) when not is_nil(user_or_peer) do
    is_blocked_by?(user_or_peer, block_type, [user])
  end

  defp is_blocked_by?(_user_or_peer, _block_types, []) do
    debug("no current_user/current_user_ids")

    nil
  end

  defp is_blocked_by?(_user_or_peer, _block_types, nil) do
    debug("no current_user")

    nil
  end

  defp is_blocked_by?(user_or_peer, _block_types, _) do
    warn(
      user_or_peer,
      "no pattern found to check blocks"
    )

    nil
  end

  @doc """
  Handles incoming Block activities from ActivityPub federation.

  A moderator closing a thread to further replies. Locking IS a block of type `:lock` on the object, so this needs no new concept: what arrives as `Lock` from the threadiverse is the same thing our own "lock a post" does. The reason travels in `summary`, as it does on a mod-removal `Delete`; we do not have anywhere to show it yet.

  ## Examples

      iex> Bonfire.Boundaries.Blocks.ap_receive_activity(blocker, activity, blocked)
  """
  def ap_receive_activity(locker, %{data: %{"type" => "Lock"} = data} = _activity, object) do
    info("apply incoming Lock")

    with {:ok, object} <- ap_receive_object_to_lock(object),
         # the group the moderator claims to act for, which this family states in `audience`
         :ok <- moderation_authority(locker, object, data["audience"]),
         {:ok, locked} <- lock(object, current_user: locker) do
      # the reason a moderator gave, which the wire carries in `summary` (as a mod-removal `Delete` does). A `Flag` keeps its comment because a flag is an Edge record with a `named` mixin; a lock creates no record, only grants, so where this goes is still open (see the group federation plan).
      maybe_store_moderation_reason(object, data["summary"])
      {:ok, locked}
    else
      e -> error(e, "Could not lock the object")
    end
  end

  def ap_receive_activity(
        unlocker,
        %{data: %{"type" => "Undo", "object" => %{"type" => "Lock"} = inner}} = _activity,
        object
      ) do
    info("apply incoming Undo of a Lock")

    with {:ok, object} <- ap_receive_object_to_lock(object),
         # reopening a thread needs the same standing as closing it, so check the group the Undo's inner Lock names
         :ok <- moderation_authority(unlocker, object, inner["audience"]),
         {:ok, unlocked} <- unlock(object, current_user: unlocker) do
      {:ok, unlocked}
    else
      e -> error(e, "Could not unlock the object")
    end
  end

  defp ap_receive_object_to_lock(%{pointer_id: pointer_id}) when is_binary(pointer_id),
    do: Bonfire.Common.Needles.get(pointer_id, skip_boundary_check: true)

  defp ap_receive_object_to_lock(%{} = object), do: {:ok, object}
  defp ap_receive_object_to_lock(other), do: error(other, "No object to lock")

  # Moderation from elsewhere only counts within a group, and only from that group's own authority. FEP-1b12's convention, which every implementor follows, is that a receiver accepts a moderation activity when its actor is listed as a moderator of the group the object belongs to, or is same-origin with that group. Note it can NOT be same-origin with the object: a moderator
  # legitimately closes a thread whose post was authored on a third instance.
  #
  # Without this, anyone who can reach our inbox could close any thread on this instance.
  # Who may moderate what is a GROUP question, so it lives with groups rather than here: this module knows how to lock an object, not who is entitled to. One call out, and if the groups extension is disabled there is no group moderation to accept, so refusing is the right fallback.
  defp moderation_authority(actor, object, group_ap_id) do
    # `audience` is a single id on the wire but a list once ingested, since addressing fields are
    # normalised on the way in. Read both shapes, or a legitimate lock is refused for its shape
    group_ap_ids = group_ap_id |> List.wrap() |> Enum.filter(&is_binary/1)

    cond do
      # an author closing their own thread, which is exactly what we let a local author do
      author?(actor, object) ->
        :ok

      # A thread in no group has no moderator collection to check against, and same-origin with the object is NOT a substitute: that would let any account on the object's instance close any thread it hosts, not just its moderators. Remote instance-admin standing is not something we can verify today (nodeinfo does not carry it, and nothing signs "I am an admin here"), so refuse rather than trust the claim. The author case above is the exception, since that one IS verifiable.
      group_ap_ids == [] ->
        error(
          actor,
          "refusing remote moderation of a thread in no group: only its author has verifiable standing"
        )

      # otherwise it is group moderation, and who may moderate what is a GROUP question, so it lives with groups rather than here: this module knows how to lock an object, not who is entitled to. Note an admin of the group's own instance passes this as same-origin, while an admin of some other instance has no standing over that group's threads `== true` deliberately: anything else, including an `{:error, …}` tuple (which is truthy, and is what `error/2` returns), must not read as permission granted
      Utils.maybe_apply(
        Bonfire.Classify.Categories,
        :remote_moderation_authority?,
        [actor, object, group_ap_ids],
        fallback_return: false
      ) == true ->
        :ok

      true ->
        error(actor, "refusing remote moderation without authority over the object or its group")
    end
  end

  defp author?(actor, object) do
    uid(actor) ==
      object
      |> repo().maybe_preload(created: [:creator])
      |> e(:created, :creator_id, nil)
  end

  defp maybe_store_moderation_reason(_object, reason) when reason in [nil, ""], do: :ok

  defp maybe_store_moderation_reason(object, reason) do
    # TODO: where to store the reason? The object may be a post, comment, or thread, etc
    # Utils.maybe_apply(Bonfire.Common.Settings, :put, [[:moderation_reason], reason, [scope: object]],
    #   fallback_return: nil
    # )
  end

  def ap_receive_activity(
        blocker,
        %{data: %{"type" => "Block"} = _data} = _activity,
        %{data: %{}} = blocked
      ) do
    info("apply incoming Block")

    with {:ok, blocked} <-
           Bonfire.Common.Utils.maybe_apply(
             Bonfire.Federate.ActivityPub.AdapterUtils,
             :get_or_fetch_character_by_ap_id,
             [blocked]
           )
           |> debug("character to_block"),
         {:ok, block} <- block(blocked, current_user: blocker) |> debug("blocked?") do
      {:ok, block}
    else
      e ->
        error(e)
    end
  end

  def ap_receive_activity(
        unblocker,
        %{data: %{"type" => "Undo", "object" => %{"type" => "Block", "object" => unblocked_id}}} =
          _activity,
        _object
      ) do
    info("apply incoming Undo Block")

    with {:ok, unblocked} <-
           Bonfire.Common.Utils.maybe_apply(
             Bonfire.Federate.ActivityPub.AdapterUtils,
             :get_or_fetch_character_by_ap_id,
             [unblocked_id]
           )
           |> debug("character to unblock"),
         {:ok, result} <- unblock(unblocked, nil, current_user: unblocker) |> debug("unblocked?") do
      {:ok, result}
    else
      e ->
        error(e)
    end
  end

  def ap_receive_activity(
        unblocker,
        %{data: %{"type" => "Undo"}} = _activity,
        %{data: %{"type" => "Block", "object" => unblocked_id}} = _block_object
      ) do
    info("apply incoming Undo Block (with separate block object)")

    with {:ok, unblocked} <-
           Bonfire.Common.Utils.maybe_apply(
             Bonfire.Federate.ActivityPub.AdapterUtils,
             :get_or_fetch_character_by_ap_id,
             [unblocked_id]
           )
           |> debug("character to unblock"),
         {:ok, result} <- unblock(unblocked, nil, current_user: unblocker) |> debug("unblocked?") do
      {:ok, result}
    else
      e ->
        error(e)
    end
  end

  defp blocked_ids_for(subjects, block_type) do
    block_circle_ids = instance_wide_circles(types_blocked(block_type))
    Circles.subject_ids_in_circles(Enums.ids(subjects), block_circle_ids)
  end

  @doc """
  Filters a list of subjects, returning only those not blocked instance-wide for the given block type.

  ## Examples

      iex> Bonfire.Boundaries.Blocks.reject_blocked([user1, user2], :ghost, :instance_wide)
      [user2]

      iex> Bonfire.Boundaries.Blocks.reject_blocked([%{id: "a"}, %{id: "b"}], :any, :instance_wide)
      [%{id: "a"}, %{id: "b"}] # if none are blocked

  Returns the same type as input (structs or IDs).
  """
  def reject_blocked(subjects, block_type \\ :any, :instance_wide) do
    blocked_ids = blocked_ids_for(subjects, block_type) |> MapSet.new()

    Enum.filter(subjects, fn
      %{id: id} -> not MapSet.member?(blocked_ids, id)
      id when is_binary(id) -> not MapSet.member?(blocked_ids, id)
    end)
  end

  @doc """
  Throws `:blocked` if any subject in the list is blocked instance-wide for the given block type.

  ## Examples

      iex> Bonfire.Boundaries.Blocks.throw_blocked!([user1, user2], :ghost, :instance_wide)
      ** (throw) :blocked

      iex> Bonfire.Boundaries.Blocks.throw_blocked!([user1], :ghost, :instance_wide)
      :ok

  Returns :ok if none are blocked.
  """
  def check_blocked!(subjects, block_type \\ :any, :instance_wide, throw_what) do
    if blocked_ids_for(subjects, block_type) != [] do
      throw(throw_what || :blocked)
    else
      subjects
    end
  end
end
