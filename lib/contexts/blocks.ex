defmodule Bonfire.Boundaries.Blocks do
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.Circles
  # alias Bonfire.Data.Identity.User
  # alias Bonfire.Data.AccessControl.Grant
  # alias Bonfire.Data.Identity.Caretaker

  def federation_module,
    do: [
      "Block"
    ]

  def types_blocked(types) when is_list(types) do
    Enum.flat_map(types, &types_blocked/1) |> Enum.uniq()
  end

  def types_blocked(type) when type in [:ghost, :ghost_them] do
    [:ghost_them]
  end

  def types_blocked(type) when type in [:silence, :silence_them] do
    [:silence_them]
  end

  def types_blocked(_) do
    [:silence_them, :ghost_them]
  end

  @doc """
  Block something for everyone on the instance (only for admins)
  """
  def instance_wide_block(user_or_instance_to_block, block_type \\ nil) do
    block(user_or_instance_to_block, block_type, :instance_wide)
  end

  def block(user_or_instance_to_block, block_type \\ nil, opts) do
    with {:ok, blocked} <- mutate(:block, user_or_instance_to_block, block_type, opts) do
      if user_or_instance_to_block != :instance_wide and opts != :instance_wide do
        me = Utils.current_user_required!(opts)
        types_blocked = types_blocked(block_type)

        # TODO: what about if I block and later unblock someone? they should probably not have to re-follow...
        if :ghost_them in types_blocked do
          debug("make the person I am ghosting unfollow me - TODO: do not federate this?")
          Utils.maybe_apply(Bonfire.Social.Follows, :unfollow, [user_or_instance_to_block, me])
        end

        if :silence_them in types_blocked do
          debug("unfollow the person I am silencing")
          Utils.maybe_apply(Bonfire.Social.Follows, :unfollow, [me, user_or_instance_to_block])
        end
      end

      {:ok, blocked}
    end
  end

  def unblock(user_or_instance_to_block, block_type \\ nil, opts) do
    mutate(:unblock, user_or_instance_to_block, block_type, opts)
  end

  defp mutate(
         block_or_unblock,
         user_or_instance_to_block,
         block_type,
         :instance_wide
       )
       when block_type in [:silence, :silence_them] do
    instance_wide_circles([:silence_me, :silence_them])
    |> info("instance_wide_circles_silenced")
    |> do_mutate_blocklists(block_or_unblock, user_or_instance_to_block, ...)
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

  # @doc "Block something for the current user (current_user should be passed in opts)"
  defp mutate(block_or_unblock, user_or_instance_to_block, block_type, opts)
       when block_type in [:silence, :silence_them] do
    current_user = Utils.current_user_required!(opts)
    silence_them = types_blocked(block_type)

    debug(
      "add silence block to both users' circles, one to my #{inspect(silence_them)} and the other to their :silence_me"
    )

    # my list of people I've silenced
    with {:ok, _ret} <-
           mutate_blocklists(
             block_or_unblock,
             user_or_instance_to_block,
             silence_them,
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

  @doc """
  Checks if a `user_or_instance` is blocked
  Pass a `block_type` (eg `:silence` or `:ghost`)
  Pass a `current_user` in `opts` or check `:instance_wide`
  """
  def is_blocked?(user_or_instance, block_type \\ :any, opts \\ [])

  def is_blocked?(user_or_instance, block_type, :instance_wide) do
    instance_wide_circles(types_blocked(block_type))
    |> info("instance_wide_circles_blocked")
    |> Bonfire.Boundaries.Circles.is_encircled_by?(user_or_instance, ...)
  end

  def is_blocked?(user_or_instance, block_type, opts) do
    info(
      opts,
      "check if blocked #{inspect(block_type)} instance-wide or per-user, if any has/have been provided in opts"
    )

    is_blocked?(user_or_instance, block_type, :instance_wide) ||
      is_blocked_by?(
        user_or_instance,
        block_type,
        opts[:user_ids] || current_user(opts)
      )
  end

  # only for admins
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

  defp mutate_blocklists(
         block_or_unblock,
         user_or_instance_add,
         block_type,
         circle_caretaker
       ) do
    circle_caretaker
    |> per_user_circles(..., block_type)
    # |> info("user:circles_to_block")
    |> repo().maybe_preload(caretaker: [caretaker: [:profile]])
    |> do_mutate_blocklists(block_or_unblock, user_or_instance_add, ...)
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
    # TODO: properly validate the inserts
    with {deleted, _} when deleted > 0 <-
           Circles.remove_from_circles(user_or_instance_to_unblock, circles) do
      {:ok, "Unblocked"}
    else
      e ->
        error(e)
        {:error, "Could not unblock"}
    end
  end

  def instance_wide_circles(block_types) when is_list(block_types) do
    Enum.map(block_types, &Bonfire.Boundaries.Circles.get_id/1)
  end

  def instance_wide_circles(block_type) do
    types_blocked(block_type)
    |> instance_wide_circles()
  end

  defp per_user_circles(current_user, block_types) when is_list(block_types) do
    Circles.get_stereotype_circles(current_user, block_types)
  end

  def user_block_circles(current_user, block_type) do
    types_blocked(block_type)
    # |> debug()
    |> per_user_circles(current_user, ...)
  end

  defp is_blocked_by?(%{} = user_or_peer, block_type, current_user_ids)
       when is_list(current_user_ids) and length(current_user_ids) > 0 do
    # info(user_or_peer, "user_or_peer to check")
    info(current_user_ids, "current_user_ids")

    block_types = types_blocked(block_type)

    current_user_ids
    |> info("user_ids")
    |> Enum.map(&per_user_circles(&1, block_types))
    # |> info("user_block_circles")
    |> Bonfire.Boundaries.Circles.is_encircled_by?(user_or_peer, ...)
  end

  defp is_blocked_by?(user_or_peer, block_type, user_id)
       when is_binary(user_id) do
    is_blocked_by?(user_or_peer, block_type, [user_id])
  end

  defp is_blocked_by?(user_or_peer, block_type, %{} = user) do
    is_blocked_by?(user_or_peer, block_type, [user])
  end

  defp is_blocked_by?(user_or_peer, _block_types, current_user_ids) do
    warn(
      user_or_peer,
      "no pattern found for user_or_peer (or current_user/current_user_ids)"
    )

    warn(
      current_user_ids,
      "no pattern found for current_user/current_user_ids (or user_or_peer)"
    )

    nil
  end

  def ap_receive_activity(
        blocker,
        %{data: %{"type" => "Block"} = _data} = _activity,
        %{data: %{}} = blocked
      ) do
    info("apply incoming Block")

    with {:ok, blocked} <-
           Bonfire.Federate.ActivityPub.AdapterUtils.get_character_by_ap_id(blocked)
           |> debug(),
         {:ok, block} <- block(blocked, :all, current_user: blocker) |> debug() do
      {:ok, block}
    else
      e ->
        error(e)
    end
  end
end
