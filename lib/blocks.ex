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
  alias Bonfire.Boundaries.Controlleds
  # alias Bonfire.Boundaries.Grants
  # alias Bonfire.Data.Identity.User
  # alias Bonfire.Data.AccessControl.Grant
  # alias Bonfire.Data.Identity.Caretaker

  @behaviour Bonfire.Federate.ActivityPub.FederationModules
  def federation_module,
    do: [
      "Block",
      # `ap_receive_activity/3` has handled this since before it was declared here, so an incoming unblock was parsed and then routed nowhere
      {"Undo", "Block"},
      # a moderator closing a thread to further replies, which is a `:lock` block on the object
      "Lock",
      {"Undo", "Lock"},
      # a group elsewhere refusing one of our moderators' actions on it
      {"Reject", "Lock"},
      {"Reject", "Block"}
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
    # resolved only to know WHAT to block, so not as anyone: a block is sometimes of something the blocker can't see (someone who ghosted them, a members-only or paid post), and an instance-wide one has no user to look it up as. Whether the block is allowed is the caller's to check
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
    # one of our moderators banning someone on behalf of a group hosted elsewhere: the ban goes to the group, and the group's echo of it is what applies it here (`ap_receive_activity/3`), so it is pending until then. With their locality loaded, which the check needs
    user = current_user(scope) |> repo().maybe_preload(character: [:peered])
    on_behalf_of = e(scope, :on_behalf_of, nil)

    elsewhere? =
      not is_nil(on_behalf_of) and
        maybe_apply(
          Bonfire.Social.Moderations,
          :moderating_elsewhere?,
          [load_for_locality_check(on_behalf_of), user],
          fallback_return: false
        )

    scope = if elsewhere?, do: Keyword.put(Keyword.new(scope), :pending, true), else: scope

    # the status, as callers show it (eg. as a flash); `lock/2` takes the record from `block_and_record/3`
    with {:ok, status, record} <- block_and_record(user_or_instance_to_block, block_type, scope) do
      # sent from the moderator, naming the group, whatever the federation box says: it only takes effect through the group
      if elsewhere?,
        do:
          maybe_federate_block(user, user_or_instance_to_block, :block,
            acting_user: user,
            on_behalf_of: load_for_locality_check(on_behalf_of),
            reason: e(scope, :reason, nil),
            record: record
          )

      {:ok, status}
    end
  end

  # the moderation log's record of it, written here for every type so there is one place that does (a lock included), and returned beside the status (nil when nobody acted), so `lock/2` can federate it and whoever applied an incoming one can link its AP activity to it
  defp block_and_record(user_or_instance_to_block, block_type, scope) do
    with {:ok, scope} <- maybe_on_behalf_of(scope),
         {who_acted, scope} = instance_wide_with_actor(scope),
         # `pending: true`: one of our moderators acting on a group hosted elsewhere, applied here once the group has (unless `apply_now:`, defaulting to config), so recorded as pending
         {:ok, status} <-
           if(
             e(scope, :pending, nil) &&
               !maybe_apply(Bonfire.Social.Moderations, :apply_now?, [scope],
                 fallback_return: true
               ),
             do: {:ok, :pending},
             else: do_block(user_or_instance_to_block, block_type, scope)
           ) do
      case maybe_record(who_acted, block_type, user_or_instance_to_block, scope) do
        {:ok, record} -> {:ok, status, record}
        _ -> {:ok, status, nil}
      end
    end
  end

  # `current_user: admin, scope: :instance_wide`: an instance-wide block that names who made it, for its record. The rest of this module takes the bare `:instance_wide`, which is also how a caller with nobody acting asks for one
  defp instance_wide_with_actor(scope) do
    if Keyword.keyword?(scope) and scope[:scope] == :instance_wide,
      do: {{current_user(scope), scope}, :instance_wide},
      else: {{e(scope, :acting_user, nil) || current_user(scope), scope}, scope}
  end

  # One record per action, its verb the type (`block` for both at once), its subject whoever acted (`acting_user` when on a group's behalf, whose group then is where it's logged). Nobody acting, nothing recorded. Through `maybe_apply` since records live in bonfire_social, which boundaries doesn't depend on
  defp maybe_record({nil, _opts}, _block_type, _object, _scope), do: nil

  defp maybe_record({subject, opts}, block_type, object, scope) do
    current_user = current_user(opts)

    maybe_apply(
      Bonfire.Social.Moderations,
      :record,
      [
        subject,
        record_verb(block_type),
        object,
        [
          reason: e(opts, :reason, nil),
          current_user: current_user,
          # where it applies: the group it was made on behalf of, or the instance
          scope:
            if(e(opts, :acting_user, nil),
              do: current_user,
              else: if(scope == :instance_wide, do: :instance_wide)
            ),
          pending: e(opts, :pending, nil)
        ]
      ],
      fallback_return: nil
    )
  end

  defp record_verb(type) when type in [:silence, :ghost, :hide, :lock], do: type
  defp record_verb(_both), do: :block

  defp do_block(user_or_instance_to_block, block_type, scope) do
    types_blocked =
      types_blocked(block_type)

    # |> debug("types_blocked for #{inspect block_type}")

    # the type as given: a missing one (or a list) would otherwise mean every type it stands for, which `mutate/4` runs one by one through each type's own clause. `List.first(types_blocked)` here made a plain `block/2` silence only, never ghost, while everything below acts on `types_blocked` as if both had happened
    # block_type || List.first(types_blocked),
    with {:ok, result} <-
           mutate(
             :block,
             user_or_instance_to_block,
             block_type,
             scope
           ) do
      # debug(result, "blooocked")

      # Severing follows is OPT-IN, because it can signal the block to the blocked person. Unfollowing when silencing would drop their follower count (and leaving removes us from their followers list). `unblock/3` does not restore the follow either, so what it costs is permanent.
      # UI may well want provide a "mute and unfollow", so it stays available, they just have to ask for it rather than have it happen unannounced.
      if e(scope, :also_unfollow_and_notify, false) and
           user_or_instance_to_block != :instance_wide and
           scope != :instance_wide do
        me = Utils.current_user_required!(scope)

        # blocking on behalf of a group (`on_behalf_of:`): its silence federates too, since it keeps someone out of the group's discussions, which other instances following the group need to know
        on_behalf_of_group? = not is_nil(e(scope, :acting_user, nil))

        if :ghost_them in types_blocked do
          # Their follow of me, so nothing about it is ours to announce: `Follows.ap_publish_activity/3` skips a non-local follower rather than trying to sign an `Undo{Follow}` as them. The `Block` below is what their server hears.
          debug("make the person I am ghosting unfollow me")

          Utils.maybe_apply(Bonfire.Social.Graph.Follows, :unfollow, [
            user_or_instance_to_block,
            me
          ])

          # ONLY for a ghost, which is the half a remote can act on. Ghosting says "they cannot see me", and `Block` is how the fediverse says that: Mastodon and everything copying it drops the follow and hides the blocker's content on receipt.
          #
          # A silence says "I do not see them", which is a MUTE, and mutes do not federate anywhere, Mastodon's are local-only. Their server cannot help me not-see them, my own feed filtering does that, so sending one would be a disclosure that buys nothing and would be read as far stronger than what was asked for.
          #
          # Blocking (both types at once) therefore emits exactly one `Block`, from this half.
          maybe_federate_block(me, user_or_instance_to_block, :block, scope)
        end

        if :silence_them in types_blocked do
          if on_behalf_of_group? do
            # a group follows nobody, and the person keeps their follow of it, since someone the group silenced may still read it. One `Block` for both halves: the ghost half above already sent it
            if :ghost_them not in types_blocked,
              do: maybe_federate_block(me, user_or_instance_to_block, :block, scope)
          else
            debug("unfollow the person I am silencing")

            Utils.maybe_apply(Bonfire.Social.Graph.Follows, :unfollow, [
              me,
              user_or_instance_to_block
            ])
          end
        end
      end

      {:ok, result}
    end
  end

  # Blocking on behalf of a group (`on_behalf_of: group`): the group is the blocker, so its own block circles hold the person, and its block ACLs, on the group and on what is published in it, deny them. Whoever acted is kept as `acting_user`, who sends whatever federates. Only someone who may moderate the group (`:mediate`) may
  defp maybe_on_behalf_of(scope) do
    case e(scope, :on_behalf_of, nil) do
      nil ->
        {:ok, scope}

      on_behalf_of ->
        acting_user = Utils.current_user(scope)

        # as an id too (eg. from a form), loaded since it becomes the blocker, whose circles hold the block
        on_behalf_of =
          if is_binary(on_behalf_of),
            do: Bonfire.Common.Needles.get!(on_behalf_of, skip_boundary_check: true),
            else: on_behalf_of

        if Bonfire.Boundaries.can?(acting_user, :mediate, on_behalf_of),
          do:
            {:ok,
             scope
             |> Keyword.new()
             |> Keyword.delete(:on_behalf_of)
             |> Keyword.merge(current_user: on_behalf_of, acting_user: acting_user)},
          else:
            error(:not_permitted, "Only someone who moderates the group may block on its behalf")
    end
  end

  # Telling their server rides on the SAME opt-in as severing the follow, because they are two halves of one choice: both reach further than our own instance can, and both are noticeable. Removing someone from our followers stops us addressing them; telling their server is what can stop a post it has ALREADY received from being shown to them, which is the case a shared inbox leaves open.
  #
  # Only for a remote person. Blocking a local one is enforced by our own boundaries, so there is nobody to tell. Except a block on behalf of a group (`on_behalf_of:`), which is for the group's followers on other instances as much as for the person's, so it goes out whoever is blocked; the scope goes along, so `ap_publish_activity/4` sends it from whoever acted.
  defp maybe_federate_block(me, user_or_instance_to_block, verb \\ :block, scope \\ []) do
    object = load_for_locality_check(user_or_instance_to_block)
    on_behalf_of_group? = not is_nil(e(scope, :acting_user, nil))

    # Not about an INSTANCE, and not about someone local. A `Block` names an actor, so blocking a whole host has no shape to send and nobody to send it to: that is local policy, enforced by our own delivery checks. And blocking someone local needs no telling, since our boundaries are the enforcement.
    #
    # ⚠️ stated as "not a Peer" rather than "is a character". The obvious allow-list spelling, `Types.object_type(object) in Config.get(:types_character_schemas, [], :bonfire)`, reads `[]` because that key is unset (the default lives at each call site, see `AdapterUtils`), so the condition is never true and every Block is silently dropped. `maybe_federate_lock/3` survives the same expression only because it asks `not in`, where an empty list fails open.
    if Types.object_type(object) != Bonfire.Data.ActivityPub.Peer and
         (on_behalf_of_group? or
            Utils.maybe_apply(Bonfire.Federate.ActivityPub.AdapterUtils, :is_local?, [object],
              fallback_return: true
            ) != true) do
      try do
        Utils.maybe_apply(
          Bonfire.Federate.ActivityPub.Outgoing,
          :maybe_federate,
          [
            me,
            verb,
            object,
            [federation_module: __MODULE__] ++
              Keyword.take(List.wrap(if Keyword.keyword?(scope), do: scope), [
                :acting_user,
                :reason,
                :on_behalf_of,
                :record
              ])
          ],
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
  Unblocks a user or instance.

  ## Examples

      iex> Bonfire.Boundaries.Blocks.unblock(user, :ghost, current_user: unblocker)
      {:ok, "Unblocked"}

      iex> Bonfire.Boundaries.Blocks.unblock(user, :silence, :instance_wide)
      {:ok, "Unblocked"}
  """
  def unblock(user_or_instance_to_unblock, block_type \\ nil, scope) do
    with {:ok, scope} <- maybe_on_behalf_of(scope),
         # lifting writes no record, so who did it isn't needed here, only the scope it names
         {_who_acted, scope} = instance_wide_with_actor(scope),
         {:ok, result} <- mutate(:unblock, user_or_instance_to_unblock, block_type, scope) do
      # unconditional, unlike the block: `ap_publish_activity/3` sends nothing unless a `Block` actually went out, so this cannot disclose a block the person kept to themselves. Leaving a remote holding a block we have lifted would be worse than telling it
      if user_or_instance_to_unblock != :instance_wide and scope != :instance_wide,
        do:
          maybe_federate_block(
            Utils.current_user_required!(scope),
            user_or_instance_to_unblock,
            :unblock,
            scope
          )

      {:ok, result}
    end
  end

  @doc """
  Closes an object to further participation: a moderator locking a thread, or a group being archived.

  A named wrapper over `block/3`, so call sites say what they mean rather than passing a `:lock` atom, and so there is ONE seam to hang outgoing federation on when it lands — no block of any kind federates today.

  ## Examples

      iex> Bonfire.Boundaries.Blocks.lock(post, current_user: moderator)
  """
  def lock(object, scope) do
    # one of our moderators locking something a group elsewhere hosts: its `Lock` goes to the group, and the group's echo of it is what locks it here (`ap_receive_activity/3`). With their locality loaded, which the check needs
    user = current_user(scope) |> repo().maybe_preload(character: [:peered])

    # as a moderator of the group it is in, when that group is hosted elsewhere
    group =
      case maybe_apply(Bonfire.Classify.Categories, :group_of_object, [object],
             fallback_return: nil
           ) do
        {:ok, _object, %{} = group} -> repo().maybe_preload(group, character: [:peered])
        _ -> nil
      end

    elsewhere? =
      maybe_apply(
        Bonfire.Social.Moderations,
        :moderating_elsewhere?,
        [group, user],
        fallback_return: false
      )

    # TODO: the grants and the record in one transaction, so neither exists without the other
    with {:ok, object} <- may_lock(object, scope),
         # the block writes the moderation log's record, with the reason if one was given
         {:ok, status, record} <-
           block_and_record(object, :lock, Keyword.put(Keyword.new(scope), :pending, elsewhere?)) do
      maybe_federate_lock(:lock, object, scope,
        reason: e(scope, :reason, nil),
        record: record,
        moderating_elsewhere: elsewhere?
      )

      # the record when one was written, so whoever applied an incoming `Lock` can link its AP activity to it (which is how a relayed copy of it is known to be applied already)
      {:ok, record || status}
    end
  end

  @doc "Reopens an object closed by `lock/2`. Needs the same standing as locking it."
  def unlock(object, scope) do
    # TODO: an `unlock` record, with `reverses:` the lock's record when there is one (a lock made before records has none)
    with {:ok, object} <- may_lock(object, scope),
         {:ok, _} = ok <- unblock(object, :lock, scope) do
      maybe_federate_lock(:unlock, object, scope)
      ok
    end
  end

  # Who may close (or reopen) a thread is a boundary question like any other, for local and remote actors alike: the object must load for them with `:grant` (its author, or whoever may change its boundary) or `:mediate` (a moderator of the group it was published in, or that group itself, through the group's ACLs). Instance admins may too, as the UI offers them. Without it anyone could lock any thread, since the grants below check nothing
  defp may_lock(object, scope) do
    current_user = current_user(scope)

    cond do
      is_nil(current_user) ->
        error(:not_permitted, "Only someone signed in can lock a thread")

      Bonfire.Boundaries.can?(current_user, :grant, :instance) ->
        case load_for_locality_check(object) do
          nil -> error(:not_found, "Could not find what to lock")
          object -> {:ok, object}
        end

      # (no `skip_boundary_check` bypass: a caller with standing established another way passes the same check, since that standing is boundaries too)
      true ->
        case Bonfire.Common.Needles.get(uid(object),
               current_user: current_user,
               verbs: {:any, [:grant, :mediate]}
             ) do
          {:ok, loaded} ->
            {:ok, load_for_locality_check(loaded)}

          _ ->
            error(
              :not_permitted,
              "Only its author, a moderator of the group it is in, or someone who may change its boundary, can lock it"
            )
        end
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
  # Emitted only when the person asked for it (`also_unfollow_and_notify`), which is what makes a block a disclosure: the remote is told outright and may show them. See `maybe_federate_block/4`.
  # `ActivityPub.block/2` severs no follows of its own, deliberately: which follow a block ends depends on the block TYPE, and `block/3` has already done it in the right direction by the time this runs.
  # Blocking on behalf of a group (`on_behalf_of:` in `block/3`, here `opts[:acting_user]`) has the group as subject, and goes out as the threadiverse keeps someone out of a community (Lemmy's `block_user.json`): sent by whoever acted, `to` Public, `cc`, `target` and `audience` the group, the reason in `summary`, and relayed by the group to its followers. Its `Undo` is addressed as the `Block` was (the fork copies it)
  def ap_publish_activity(subject, verb, object, opts) when verb in [:block, :unblock] do
    # the group, given when the moderator is the one sending (a group hosted elsewhere), else the subject the block was made as
    on_behalf_of = e(opts, :on_behalf_of, nil) || if e(opts, :acting_user, nil), do: subject

    with {:ok, actor} <-
           ActivityPub.Actor.get_cached(pointer: e(opts, :acting_user, nil) || subject),
         {:ok, blocked_actor} <- ActivityPub.Actor.get_cached(pointer: object),
         {:ok, activity} <- publish_block(verb, actor, blocked_actor, on_behalf_of, opts) do
      if on_behalf_of,
        do:
          maybe_apply(Bonfire.Federate.ActivityPub.AdapterUtils, :maybe_group_relays, [
            on_behalf_of,
            activity
          ])

      {:ok, activity}
    else
      :ok -> :ok
      e -> error(e, "Could not federate the #{verb}")
    end
  end

  def ap_publish_activity(subject, verb, object, opts) when verb in [:lock, :unlock] do
    with {:ok, actor} <- ActivityPub.Actor.get_cached(pointer: subject),
         {:ok, ap_object} <- ActivityPub.Object.get_cached(pointer: object) do
      params =
        %{actor: actor, object: ap_object}
        # the reason, which Lemmy logs from `summary`; falling back when none was given, as every moderator activity does (`Bonfire.Social.Moderations.summary/2`)
        |> Enums.maybe_put(
          :summary,
          maybe_apply(Bonfire.Social.Moderations, :summary, [opts[:reason], verb],
            fallback_return: opts[:reason]
          )
        )
        # the group the thread is in, which is what a receiver checks a moderator's standing against, as Lemmy sends it on every community lock
        |> Enums.maybe_put(
          :audience,
          maybe_apply(
            Bonfire.Federate.ActivityPub.AdapterUtils,
            :maybe_determine_audience,
            [object],
            fallback_return: nil
          )
        )
        # the lock's moderation record, so the stored AP activity points back to it. Never the locked object's own id, which its AP object already holds
        |> Enums.maybe_put(:pointer, opts[:record])

      with {:ok, activity} <-
             (case verb do
                :lock -> ActivityPub.lock(params)
                :unlock -> ActivityPub.unlock(params)
              end) do
        # the group's followers hear of it through the group, as for every activity in a group we host
        maybe_apply(Bonfire.Federate.ActivityPub.AdapterUtils, :maybe_group_relays, [
          object,
          activity
        ])

        {:ok, activity}
      end
    else
      e -> error(e, "Could not find the actor or object to #{verb}")
    end
  end

  defp publish_block(:block, actor, blocked_actor, nil = _on_behalf_of, _opts),
    do: ActivityPub.block(%{actor: actor, object: blocked_actor})

  defp publish_block(:block, actor, blocked_actor, on_behalf_of, opts) do
    with {:ok, %{ap_id: on_behalf_of_ap_id}} <- ActivityPub.Actor.get_cached(pointer: on_behalf_of) do
      ActivityPub.block(%{
        actor: actor,
        object: blocked_actor,
        to: [ActivityPub.Config.public_uri()],
        cc: [on_behalf_of_ap_id],
        target: on_behalf_of_ap_id,
        audience: on_behalf_of_ap_id,
        summary:
          maybe_apply(Bonfire.Social.Moderations, :summary, [opts[:reason], :block],
            fallback_return: opts[:reason]
          ),
        # its moderation record, so the group's echo of it is known as ours and finds it
        pointer: opts[:record]
      })
    end
  end

  # only when we actually sent the `Block`
  defp publish_block(:unblock, actor, blocked_actor, _on_behalf_of, _opts) do
    case ActivityPub.Object.fetch_latest_block(actor, blocked_actor) do
      %{} = _block ->
        ActivityPub.unblock(%{actor: actor, object: blocked_actor})

      _ ->
        debug("no Block was ever sent for this pair, so there is nothing to undo")
        :ok
    end
  end

  # Callers pass an id as readily as a struct (the block live handler and the locking one both pass ids), and the locality checks below deliberately RAISE rather than guessing when `:peered` is not loaded. So load it here, mirroring what `AdapterUtils.preload_peered/1` asks of an object.
  defp load_for_locality_check(object_or_id) do
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
  end

  # `publish_opts` reach `ap_publish_activity/4` through `Outgoing.maybe_federate/4`: the lock's moderation `record` and its `reason`
  defp maybe_federate_lock(verb, object_or_id, scope, publish_opts \\ []) do
    object = load_for_locality_check(object_or_id)

    character_schemas =
      Bonfire.Common.Config.get(:types_character_schemas, [], :bonfire)

    # and only for objects WE host: applying an incoming `Lock` goes through this same function (`ap_receive_activity/3` below, and `Threads.ap_receive_comments_enabled/4` for the `commentsEnabled` form), so announcing a remote object's lock would echo the origin's own decision back at the fediverse as though it were ours. Or one of OUR moderators locking something a group elsewhere hosts, which is theirs to send, to that group
    if Types.object_type(object) not in character_schemas and
         (publish_opts[:moderating_elsewhere] == true or
            Utils.maybe_apply(Bonfire.Federate.ActivityPub.AdapterUtils, :is_local?, [object],
              fallback_return: false
            ) == true) do
      try do
        Utils.maybe_apply(
          Bonfire.Federate.ActivityPub.Outgoing,
          :maybe_federate,
          [current_user(scope), verb, object, [federation_module: __MODULE__] ++ publish_opts],
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

  # Locking or hiding an object attaches the ONE ACL for that kind of block (declared in config: `locked`, `hidden`, and each person's `hidden_by_me`), and undoing it detaches it. Nothing is written into the object's own ACL, so a lock and a hide no longer share grants, and undoing one leaves the other alone.
  defp mutate(block_or_unblock, object, block_type, scope) when block_type in [:lock, :hide] do
    with {:ok, acl_id} <- object_block_acl_id(block_type, scope, block_or_unblock == :block) do
      done =
        case block_or_unblock do
          :block -> Controlleds.add_acls(object, acl_id)
          :unblock -> Controlleds.remove_acls(object, [acl_id])
        end

      case {done, block_or_unblock, block_type} do
        {{:error, e}, _, _} -> error(e, l("Could not change it"))
        {_, :block, :lock} -> {:ok, l("Locked")}
        {_, :unblock, :lock} -> {:ok, l("Unlocked")}
        {_, :block, :hide} -> {:ok, l("Hidden")}
        {_, :unblock, :hide} -> {:ok, l("Unhidden")}
      end
    end
  end

  # Replaced by the clause above (one shared ACL per kind of block, attached and detached), as these wrote grants into the object's own ACL, where a lock and a hide overlapped: both deny `:reply`, so unhiding instance-wide also reopened a locked thread, and neither could be told apart from the other. Grants they already wrote are left as they are: they still deny what they did, but aren't read as a lock or hide, nor removed on undo.
  # defp mutate(:block, object_to_hide, :hide, scope) do
  #   current_user = current_user(scope)
  #   acl = Acls.get_or_create_object_custom_acl(object_to_hide, current_user || scope)
  #
  #   who_to_hide_it_from =
  #     if scope == :instance_wide do
  #       # hiding instance-wide means we hide for these circles
  #       instance_wide_circles([:guest, :local, :activity_pub])
  #     else
  #       current_user
  #     end
  #
  #   granted =
  #     Grants.grant_role(who_to_hide_it_from, acl, :can_only_read,
  #       current_user: current_user,
  #       scope: scope
  #     )
  #
  #   if Enums.all_ok?(granted) do
  #     {:ok, l("Hidden")}
  #   else
  #     error(granted, l("Could not hide it"))
  #   end
  # end
  #
  # defp mutate(:unblock, object_to_hide, :hide, scope) do
  #   current_user = current_user(scope)
  #   acl = Acls.get_or_create_object_custom_acl(object_to_hide, current_user || scope)
  #
  #   who_to_unhide_for =
  #     if scope == :instance_wide do
  #       instance_wide_circles([:guest, :local, :activity_pub])
  #     else
  #       current_user
  #     end
  #
  #   removed =
  #     Grants.remove_role(who_to_unhide_for, acl, :can_only_read,
  #       current_user: current_user,
  #       scope: scope
  #     )
  #
  #   if Enums.all_ok?(removed) do
  #     {:ok, l("Unhidden")}
  #   else
  #     error(removed, l("Could not unhide it"))
  #   end
  # end
  #
  # defp mutate(:block, object_to_lock, :lock, scope) do
  #   current_user = current_user(scope)
  #   acl = Acls.get_or_create_object_custom_acl(object_to_lock, current_user || scope)
  #
  #   who_to_lock = instance_wide_circles([:guest, :local, :activity_pub])
  #
  #   granted =
  #     Grants.grant_role(who_to_lock, acl, :cannot_participate,
  #       current_user: current_user,
  #       scope: scope
  #     )
  #
  #   if Enums.all_ok?(granted) do
  #     {:ok, l("Locked")}
  #   else
  #     error(granted, l("Could not lock it"))
  #   end
  # end
  #
  # defp mutate(:unblock, object_to_unlock, :lock, scope) do
  #   current_user = current_user(scope)
  #   acl = Acls.get_or_create_object_custom_acl(object_to_unlock, current_user || scope)
  #
  #   who_to_unlock = instance_wide_circles([:guest, :local, :activity_pub])
  #
  #   # also the ladder rung, which is what threads locked before `:cannot_participate` existed carry, so those reopen fully too
  #   granted =
  #     Grants.remove_role(who_to_unlock, acl, :cannot_participate,
  #       current_user: current_user,
  #       scope: scope
  #     ) ++
  #       Grants.remove_role(who_to_unlock, acl, :cannot_participate_or_more,
  #         current_user: current_user,
  #         scope: scope
  #       )
  #
  #   if Enums.all_ok?(granted) do
  #     {:ok, l("Unlocked")}
  #   else
  #     error(granted, l("Could not unlock it"))
  #   end
  # end

  # The ACL a lock or hide attaches. A lock applies to everyone whoever does it; a hide is instance-wide or one person's own, theirs created the first time they hide something (`create?`), since most people never do
  defp object_block_acl_id(:lock, _scope, _create?), do: {:ok, Acls.get_id!(:locked)}
  defp object_block_acl_id(:hide, :instance_wide, _create?), do: {:ok, Acls.get_id!(:hidden)}

  defp object_block_acl_id(:hide, scope, create?) do
    case current_user(scope) do
      nil ->
        error(:not_permitted, "Only someone signed in can hide something for themselves")

      user ->
        case hidden_by_me_acl(user) do
          %{} = acl ->
            {:ok, id(acl)}

          nil when create? ->
            Bonfire.Boundaries.Scaffold.create_missing_block_boundaries(user, [:hidden_by_me])

            case hidden_by_me_acl(user) do
              %{} = acl -> {:ok, id(acl)}
              _ -> error(:not_found, "Could not create the ACL for what they hide")
            end

          # nothing to undo for someone who never hid anything
          nil ->
            error(:not_found, "Nothing hidden")
        end
    end
  end

  defp hidden_by_me_acl(user),
    do:
      Bonfire.Boundaries.find_caretaker_stereotype(
        user,
        [Acls.get_id!(:hidden_by_me)],
        Bonfire.Data.AccessControl.Acl
      )

  # a `nil`/`:any`/`:block` block type means "all block types": delegate to the per-type paths so the `:silence` clauses (which also maintain the `:silence_me` reverse-index that boundary queries filter on) are used. The generic clauses below only touch `:silence_them`/`:ghost_them`, so a plain `block/2`/`unblock/2` (nil type) or `block(x, :block, scope)` would otherwise leave `:silence_me` dangling (and a later per-type `unblock(x, :silence, scope)` would fail finding nothing to remove there). Works for both per-user and instance-wide scopes (each delegated type re-dispatches to its own clause).
  defp mutate(block_or_unblock, user_or_instance_to_block, block_type, scope)
       when block_type in [nil, :any, :block] or is_list(block_type) do
    block_types = if is_list(block_type), do: block_type, else: [:ghost, :silence]

    results =
      Enum.map(block_types, &mutate(block_or_unblock, user_or_instance_to_block, &1, scope))

    case block_or_unblock do
      # a ghost and a silence do opposite-facing jobs, so a block is done only when every one of them is: reporting the first success would tell someone they are blocked when only half of it applied. Adding to a circle that already holds them still succeeds, so a block has no "nothing to do" case to excuse
      :block ->
        Enums.first_ok_if_all_ok(results)

      # an unblock CAN legitimately have nothing to do on one side (lifting a block that was only ever a silence), so it succeeds when any of them removed something
      :unblock ->
        Enums.first_ok_or_error(results)
    end
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

  # an object's lock or hide is whether the ACL for it is attached (see `mutate/4`), not circles. A boundary that simply allows no replies is not a lock, since that's a preset rather than the `locked` ACL
  def is_blocked?(object, :lock, _scope),
    do: Controlleds.has_any_acl?(object, [Acls.get_id!(:locked)])

  def is_blocked?(object, :hide, :instance_wide),
    do: Controlleds.has_any_acl?(object, [Acls.get_id!(:hidden)])

  def is_blocked?(object, :hide, opts) do
    with %{} = user <- current_user(opts),
         %{} = acl <- hidden_by_me_acl(user) do
      Controlleds.has_any_acl?(object, [id(acl)])
    else
      # signed out, or never hid anything
      _ -> false
    end
  end

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
  # The group elsewhere REFUSED our moderator's `Lock`: its request is refused, and the lock undone here in case it was applied at once (`apply_now:`), so our copy doesn't say what the group didn't
  def ap_receive_activity(
        _rejecter,
        %{data: %{"type" => "Reject"}} = _activity,
        %{local: true, data: %{"type" => "Lock", "actor" => actor} = data} = ours
      ) do
    info("the group refused our moderator's Lock")

    maybe_apply(Bonfire.Social.Moderations, :refuse_applied, [
      ours,
      fn _record ->
        # only when it was applied: a lock waiting for the group (the default) attached no `locked` ACL to take off
        with {:ok, %{pointer_id: object_id}} when is_binary(object_id) <-
               ActivityPub.Object.get_cached(ap_id: ActivityPub.Object.get_ap_id(data["object"])),
             true <- is_blocked?(object_id, :lock),
             {:ok, moderator} <- ActivityPub.Actor.get_cached(ap_id: actor) do
          mutate(:unblock, object_id, :lock, current_user: moderator.pointer_id)
        end
      end
    ])
  end

  # The group elsewhere REFUSED our moderator's ban: its request is refused, and the ban lifted here in case it was applied at once (`apply_now:`): taken out of the group's block circles for the type it was recorded as, which changes nothing if it never put them there
  def ap_receive_activity(
        _rejecter,
        %{data: %{"type" => "Reject"}} = _activity,
        %{local: true, data: %{"type" => "Block", "target" => target, "actor" => actor} = data} =
          ours
      )
      when not is_nil(target) do
    info("the group refused our moderator's ban")

    maybe_apply(Bonfire.Social.Moderations, :refuse_applied, [
      ours,
      fn record ->
        with {:ok, %{__struct__: Bonfire.Classify.Category} = group} <-
               maybe_apply(
                 Bonfire.Federate.ActivityPub.AdapterUtils,
                 :get_by_url_ap_id_or_username,
                 [ActivityPub.Object.get_ap_id(target)]
               ),
             {:ok, banned} <-
               maybe_apply(
                 Bonfire.Federate.ActivityPub.AdapterUtils,
                 :get_or_fetch_character_by_ap_id,
                 [ActivityPub.Object.get_ap_id(data["object"])]
               ),
             # loaded, since blocking on a group's behalf checks they may moderate it
             {:ok, moderator} <-
               maybe_apply(
                 Bonfire.Federate.ActivityPub.AdapterUtils,
                 :get_or_fetch_character_by_ap_id,
                 [actor]
               ),
             {:ok, scope} <- maybe_on_behalf_of(current_user: moderator, on_behalf_of: group) do
          mutate(:unblock, banned, recorded_block_type(record), scope)
        end
      end
    ])
  end

  # the block type a moderation record of a ban was written as (its verb), else a silence, which is what a ban from a community means
  defp recorded_block_type(record) do
    with %{} <- record,
         verb_id when is_binary(verb_id) <-
           record |> repo().maybe_preload(:activity) |> e(:activity, :verb_id, nil) do
      Bonfire.Boundaries.Verbs.get_slug(verb_id)
    end || :silence
  end

  # OUR moderator's `Lock`, relayed back by the group elsewhere that applied it (`lock/2` sent it, pending): that is what applies it here, if it's still waiting (the stored activity points at its moderation record)
  def ap_receive_activity(locker, %{local: true, data: %{"type" => "Lock"}} = activity, object) do
    info("our moderator's Lock, applied by the group")

    with {:ok, object} <- ap_receive_object_to_lock(object) do
      maybe_apply(
        Bonfire.Social.Moderations,
        :confirm_applied,
        [activity, fn _record -> do_block(object, :lock, current_user: locker) end],
        # with no records (social not available) nothing was pending, so just apply it
        fallback_fun: fn _activity, apply -> apply.(nil) end
      )
    end
  end

  def ap_receive_activity(locker, %{data: %{"type" => "Lock"} = data} = activity, object) do
    info("apply incoming Lock")

    # standing is checked by `lock/2` like anyone else's: a remote moderator is in the mirrored group's moderators circle, which its ACL on the object names. The `audience` the activity claims is not trusted for it
    with {:ok, object} <- ap_receive_object_to_lock(object),
         {:ok, locked} <-
           with_moderators_resynced(object, fn -> lock(object, current_user: locker) end) do
      # the reason a moderator gave, which the wire carries in `summary` (as a mod-removal `Delete` does). A `Flag` keeps its comment because a flag is an Edge record with a `named` mixin; a lock creates no record, only grants, so where this goes is still open (see the group federation plan).
      maybe_store_moderation_reason(object, data["summary"])
      maybe_relay_received(object, activity)
      {:ok, locked}
    else
      e -> error(e, "Could not lock the object")
    end
  end

  def ap_receive_activity(
        unlocker,
        %{data: %{"type" => "Undo", "object" => %{"type" => "Lock"}}} = activity,
        object
      ) do
    info("apply incoming Undo of a Lock")

    # reopening needs the same standing as closing, which `unlock/2` checks
    with {:ok, object} <- ap_receive_object_to_lock(object),
         {:ok, unlocked} <-
           with_moderators_resynced(object, fn -> unlock(object, current_user: unlocker) end) do
      maybe_relay_received(object, activity)
      {:ok, unlocked}
    else
      e -> error(e, "Could not unlock the object")
    end
  end

  # A remote moderator's action on something in a group WE host, once applied, is passed on unchanged by the group to its followers, as Lemmy's communities do (`RawAnnouncableActivities::receive` → `AnnounceActivity::send(self, …)`): their copies of the group need it, and it is how the moderator's own instance learns the group applied it. A no-op for a group we only mirror (`maybe_group_relays/2` relays only for a local group)
  defp maybe_relay_received(object, activity) do
    maybe_apply(
      Bonfire.Federate.ActivityPub.AdapterUtils,
      :maybe_group_relays,
      [object, activity],
      fallback_return: nil
    )
  end

  # a remote moderator refused here may have been added since we last synced the group's moderators, so the refusal re-syncs them from the origin and tries again (`Categories.with_moderators_resynced/2`); through `maybe_apply` since boundaries doesn't depend on classify, which without it just runs the action
  defp with_moderators_resynced(object, action) do
    maybe_apply(Bonfire.Classify.Categories, :with_moderators_resynced, [object, action],
      fallback_fun: fn _object, action -> action.() end
    )
  end

  defp receive_block_on_behalf_of(block_or_unblock, sender, target, blocked, activity) do
    with {:ok, %{__struct__: Bonfire.Classify.Category} = on_behalf_of} <-
           maybe_apply(
             Bonfire.Federate.ActivityPub.AdapterUtils,
             :get_by_url_ap_id_or_username,
             [ActivityPub.Object.get_ap_id(target)],
             fallback_return: nil
           ),
         {:ok, blocked} <-
           maybe_apply(
             Bonfire.Federate.ActivityPub.AdapterUtils,
             :get_or_fetch_character_by_ap_id,
             [blocked]
           ) do
      case with_moderators_resynced(on_behalf_of, fn ->
             apply(__MODULE__, block_or_unblock, [
               blocked,
               :silence,
               [current_user: sender, on_behalf_of: on_behalf_of]
             ])
           end) do
        {:ok, _} = done ->
          maybe_relay_received(on_behalf_of, activity)
          done

        refused ->
          refused
      end
    else
      e -> error(e, "Could not apply a block on behalf of a group")
    end
  end

  defp ap_receive_object_to_lock(%{pointer_id: pointer_id}) when is_binary(pointer_id),
    do: Bonfire.Common.Needles.get(pointer_id)

  defp ap_receive_object_to_lock(%{} = object), do: {:ok, object}
  defp ap_receive_object_to_lock(other), do: error(other, "No object to lock")

  # Replaced by the verb check in `may_lock/2`, which local and remote actors now both go through: a remote moderator passes by being in the mirrored group's moderators circle (filled from its `attributedTo`), which the group's ACL on the object names, rather than by the membership test and same-host rule below. Same-host is dropped on purpose: FEP-1b12 says the actor MUST be listed in `attributedTo`.
  # defp moderation_authority(actor, object, group_ap_id) do
  #   group_ap_ids = group_ap_id |> List.wrap() |> Enum.filter(&is_binary/1)
  #
  #   cond do
  #     author?(actor, object) ->
  #       :ok
  #
  #     group_ap_ids == [] ->
  #       error(
  #         actor,
  #         "refusing remote moderation of a thread in no group: only its author has verifiable standing"
  #       )
  #
  #     Utils.maybe_apply(
  #       Bonfire.Classify.Categories,
  #       :remote_moderation_authority?,
  #       [actor, object, group_ap_ids],
  #       fallback_return: false
  #     ) == true ->
  #       :ok
  #
  #     true ->
  #       error(actor, "refusing remote moderation without authority over the object or its group")
  #   end
  # end
  #
  # defp author?(actor, object) do
  #   uid(actor) ==
  #     object
  #     |> repo().maybe_preload(created: [:creator])
  #     |> e(:created, :creator_id, nil)
  # end

  defp maybe_store_moderation_reason(_object, reason) when reason in [nil, ""], do: :ok

  defp maybe_store_moderation_reason(object, reason) do
    # TODO: replaced by passing the `summary` to `lock/2` as `reason:`, so a remote moderator's lock becomes a record with them as subject, linked to the AP activity it came from
    # Utils.maybe_apply(Bonfire.Common.Settings, :put, [[:moderation_reason], reason, [scope: object]],
    #   fallback_return: nil
    # )
  end

  # A `Block` with `target` a group we mirror, sent by one of its moderators (the threadiverse's way of keeping someone out of a community, Lemmy's `block_user.json`): it keeps them from taking part, which is our silence, made on the group's behalf by the sender, who needs `:mediate` on the mirror (`on_behalf_of:`), its moderators re-synced on a refusal. Without `target`, the sender's own block (the clauses after these)
  # OUR moderator's ban, relayed back by the group elsewhere that applied it (`block/3` sent it, pending): that is what applies it here, if it's still waiting, as the type it was recorded as
  def ap_receive_activity(
        moderator,
        %{local: true, data: %{"type" => "Block", "target" => target}} = activity,
        %{data: %{}} = blocked
      )
      when not is_nil(target) do
    info("our moderator's ban, applied by the group")

    maybe_apply(
      Bonfire.Social.Moderations,
      :confirm_applied,
      [
        activity,
        fn record ->
        with {:ok, %{__struct__: Bonfire.Classify.Category} = group} <-
               maybe_apply(
                 Bonfire.Federate.ActivityPub.AdapterUtils,
                 :get_by_url_ap_id_or_username,
                 [ActivityPub.Object.get_ap_id(target)]
               ),
             {:ok, blocked} <-
               maybe_apply(
                 Bonfire.Federate.ActivityPub.AdapterUtils,
                 :get_or_fetch_character_by_ap_id,
                 [blocked]
               ),
             {:ok, scope} <- maybe_on_behalf_of(current_user: moderator, on_behalf_of: group) do
          do_block(blocked, recorded_block_type(record), scope)
        end
      end
      ],
      # with no records (social not available) nothing was pending, so just apply it
      fallback_fun: fn _activity, apply -> apply.(nil) end
    )
  end

  def ap_receive_activity(
        blocker,
        %{data: %{"type" => "Block", "target" => target}} = activity,
        %{data: %{}} = blocked
      )
      # an id, or the target's whole object as the fork expands it on the way in
      when not is_nil(target) do
    info("apply incoming Block on behalf of a group")
    receive_block_on_behalf_of(:block, blocker, target, blocked, activity)
  end

  def ap_receive_activity(
        unblocker,
        %{
          data: %{
            "type" => "Undo",
            "object" => %{"type" => "Block", "object" => blocked_id, "target" => target}
          }
        } = activity,
        _object
      )
      when not is_nil(target) do
    info("apply incoming Undo of a Block on behalf of a group")
    receive_block_on_behalf_of(:unblock, unblocker, target, blocked_id, activity)
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
