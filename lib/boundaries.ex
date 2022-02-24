defmodule Bonfire.Boundaries do
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration

  alias Bonfire.Data.Identity.User
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.Identity.Caretaker
  alias Bonfire.Boundaries.Accesses

  @visibility_verbs [:see, :read]

  @doc """
  Assigns the user as the caretaker of the given object or objects,
  replacing the existing caretaker, if any.
  """
  def take_care_of!(things, user) when is_list(things) do
    repo().insert_all(Caretaker, Enum.map(things, &(%{id: Utils.ulid(&1), caretaker_id: Utils.ulid(user)})), on_conflict: :nothing, conflict_target: [:id]) #|> debug
    Enum.map(things, fn thing ->
      case thing do
        %{caretaker: _} ->
          Map.put(thing, :caretaker, %Caretaker{id: thing.id, caretaker_id: Utils.ulid(user), caretaker: user})
        _ -> thing
      end
    end)
  end
  def take_care_of!(thing, user), do: hd(take_care_of!([thing], user))

  defp block_type(:ghost) do
    [:ghost]
  end
  defp block_type(:silence) do
    [:silence]
  end
  defp block_type(_) do
    [:silence, :ghost]
  end

  @doc """
  Block something for everyone on the instance (only doable by admins)
  """
  def instance_wide_block(user_to_block, block_type) do
    block(user_to_block, block_type, :instance_wide)
  end

  def block(user_to_block, block_type, :instance_wide) do
    instance_wide_block_circles(block_type)
    |> debug("instance_wide_block_circles")
    |> block_circles(user_to_block, ...)
  end

  @doc """
  Block something for the current user (current_user should be passed in opts)
  """
  def block(user_to_block, block_type, opts) do
    Utils.current_user(opts)
    |> user_block_circles(..., block_type)
    |> debug("user_block_circles")
    |> block_circles(user_to_block, ...)
  end

  defp block_circles(user_to_block, circles) do
    with done when is_list(done) <- Circles.add_to_circles(user_to_block, circles) do # TODO: properly validate the inserts
        {:ok, "Blocked"}
    else e ->
      error(e)
      {:error, "Could not block"}
    end
  end

  defp instance_wide_block_circles(block_type) do
    block_type(block_type)
    |> Enum.map(&Bonfire.Boundaries.Circles.get_id/1)
  end

  defp user_block_circles(user, block_type), do: Circles.get_stereotype_circles(user, block_type(block_type))

  def is_blocked?(peered, block_type \\ :any, opts \\ [])

  def is_blocked?(user, block_type, :instance_wide) do
    Bonfire.Boundaries.Circles.is_encircled_by?(user, instance_wide_block_circles(block_type))
  end

  def is_blocked?(user, block_type, opts) do
    debug(opts, "TODO: also check per-user")
    Bonfire.Boundaries.Circles.is_encircled_by?(user, instance_wide_block_circles(block_type))
      ||
    is_blocked_by?(user, block_type, opts[:user_ids] || ulid(current_user(opts)))
  end

  def is_blocked_by?(user, block_type, user_ids) when is_list(user_ids) and length(user_ids)>0 do
    dump(user, "user")

    user_ids
    |> dump("user_ids")
    |> Enum.map(&user_block_circles(&1, block_type))
    |> dump("user_block_circles")
    |> Bonfire.Boundaries.Circles.is_encircled_by?(user, ...)
  end
  def is_blocked_by?(user, block_type, user_id) when is_binary(user_id) do
    is_blocked_by?(user, block_type, [user_id])
  end
  def is_blocked_by?(user, block_type, %{} = user) do
    is_blocked_by?(user, block_type, [user])
  end
  def is_blocked_by?(_user, _, _) do
    nil
  end


  def user_default_boundaries() do # FIXME: this vs acls/0 ?
    Config.get!(:user_default_boundaries)
  end

  def preset(preset) when is_binary(preset), do: preset
  def preset(preset_and_custom_boundary), do: maybe_from_opts(preset_and_custom_boundary, :boundary)

  def maybe_custom_circles_or_users(preset_and_custom_boundary), do: maybe_from_opts(preset_and_custom_boundary, :to_circles)

  def maybe_from_opts(preset_and_custom_boundary, key, fallback \\ []) when is_list(preset_and_custom_boundary) do
    preset_and_custom_boundary[key] || fallback
  end
  def maybe_from_opts(_preset_and_custom_boundary, _key, fallback), do: fallback

  def maybe_compose_ad_hoc_acl(base_acl, user) do
  end

  def maybe_make_visible_for(current_user, object, circle_ids \\ []), do: maybe_grant_access_to(current_user, object, circle_ids, @visibility_verbs)

  @doc "Grant verbs to an object to a list of circles + the user"
  def maybe_grant_access_to(current_user, object, circle_ids \\ [], verbs \\ @visibility_verbs)

  def maybe_grant_access_to(%{id: current_user_id} = current_user, object_id, circle_ids, verbs) when is_list(circle_ids) and is_binary(object_id) do

    opts = [current_user: current_user]
    grant_subjects = Utils.ulid(circle_ids ++ [current_user]) #|> debug(label: "maybe_grant_access_to")

    error("TODO: Refactor needed to grant #{inspect verbs} on object #{inspect object_id} to #{inspect grant_subjects}")

    # with {:ok, %{id: acl_id}} <- Bonfire.Boundaries.Acls.create(opts),# |> debug(label: "acled"),
    # {:ok, _controlled} <- Bonfire.Boundaries.Controlleds.create(%{id: object_id, acl_id: acl_id}), #|> debug(label: "ctled"),
    # {:ok, grant} <- Bonfire.Boundaries.Grants.grant(grant_subjects, acl_id, verbs, true, opts) do
    #   # debug(one_grant: grant)
    #   {:ok, :granted}
    # else
    #   grants when is_list(grants) -> # TODO: check for failures?
    #     # debug(many_grants: grants)
    #     {:ok, :granted}

    #   e -> {:error, e}
    # end
  end

  def maybe_grant_access_to(current_user, %{id: object_id} = _object, circles, verbs) do
    maybe_grant_access_to(current_user, object_id, circles, verbs)
  end

  def maybe_grant_access_to(current_user, object, circle, verbs) when not is_list(circle) do
    maybe_grant_access_to(current_user, object, [circle], verbs)
  end

  def maybe_grant_access_to(user_or_account_id, object, circles, verbs) when is_binary(user_or_account_id) do
    with {:ok, user_or_account} <- Bonfire.Common.Pointers.get(user_or_account_id, skip_boundary_check: true) do
      maybe_grant_access_to(user_or_account, object, circles, verbs)
    else _ ->
      warn("Boundaries.maybe_grant_access_to expected a user or account (or an ID of the same) as first param, got #{inspect user_or_account_id}")
      :skipped
    end
  end

  def maybe_grant_access_to(_, _, _, _) do
    warn("Boundaries.maybe_grant_access_to didn't receive an expected pattern in params")
    :skipped
  end

end
