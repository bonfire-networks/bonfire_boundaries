defmodule Bonfire.Boundaries.Allowlist do
  @moduledoc """
  Generic circle-based allowlist checks for users and instances.

  Mirrors `Bonfire.Boundaries.Blocks` but for `:allow_them` stereotype circles.
  Does NOT handle AP-specific types (`Peered`, `ActivityPub.Actor`) — callers in
  `Bonfire.Federate.ActivityPub.Instances` and `Peered` resolve those before calling here.
  """

  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.Circles

  @stereotypes [:allow_them]

  @doc """
  Check whether a subject is in an allowlist circle, instance-wide and/or per-user.

  Accepts any subject that `Circles.is_encircled_by?` understands (ID, struct, `%Circle{}`).
  """
  def is_allowlisted?(subject, opts \\ [])

  def is_allowlisted?(subject, :instance_wide) when not is_nil(subject) do
    is_allowlisted_instance_wide?(subject)
  end

  def is_allowlisted?(subject, opts) when not is_nil(subject) do
    is_allowlisted_instance_wide?(subject, opts) ||
      is_allowlisted_per_user?(subject, opts)
  end

  def is_allowlisted?(_, _) do
    warn("no subject provided to check")
    false
  end

  @doc """
  Check whether a subject is in an instance-wide `:allow_them` circle.

  Prefers a set pre-resolved for the whole candidate set (`opts[:resolved][:allowlisted_ids]`, built
  by `BoundariesMRF.filter/2`) to avoid per-subject n+1; falls back to a single query otherwise.
  """
  def is_allowlisted_instance_wide?(subject, opts \\ [])

  def is_allowlisted_instance_wide?(subject, opts) when not is_nil(subject) do
    case ed(opts, :resolved, :allowlisted_ids, nil) do
      %MapSet{} = allowlisted_ids ->
        uid(subject) in allowlisted_ids

      _ ->
        Circles.ids_for_stereotypes(@stereotypes)
        |> Circles.is_encircled_by?(subject, ...)
    end
  end

  def is_allowlisted_instance_wide?(_, _), do: false

  @doc """
  Batch pair of `is_allowlisted_instance_wide?/2`: given many `subjects`, returns a `MapSet` of those
  that ARE in an instance-wide `:allow_them` circle, in a single query. Used by `BoundariesMRF.filter/2`
  to pre-resolve the whole candidate set (put in `opts[:resolved][:allowlisted_ids]`).
  """
  def instance_wide_allowlisted_subset(subjects) when is_list(subjects) do
    Circles.encircled_subset(subjects, Circles.ids_for_stereotypes(@stereotypes))
  end

  @doc """
  Check whether a subject is in any of the given user(s)' per-user `:allow_them` circles.

  Prefers a `%{user_id => MapSet(subject_ids)}` pre-resolved for the whole candidate+user set
  (`opts[:resolved][:allowlisted_by_user]`, built by `BoundariesMRF.filter/2`) to avoid per-subject
  n+1; falls back to a single query otherwise.
  """
  def is_allowlisted_per_user?(subject, opts \\ [])

  def is_allowlisted_per_user?(subject, opts) when not is_nil(subject) do
    user_ids = e(opts, :user_ids, nil) || current_user(opts)

    case ed(opts, :resolved, :allowlisted_by_user, nil) do
      %{} = by_user ->
        subject_id = uid(subject)

        user_ids
        |> List.wrap()
        |> Enum.any?(fn user ->
          MapSet.member?(Map.get(by_user, uid(user), MapSet.new()), subject_id)
        end)

      _ ->
        is_allowlisted_by?(subject, user_ids)
    end
  end

  def is_allowlisted_per_user?(_, _), do: false

  @doc """
  Batch pair of `is_allowlisted_per_user?/2`: returns `%{user_id => MapSet(subject_ids)}` for which of
  `subjects` are in each user's per-user `:allow_them` circles. One `encircle` query per user (built
  once, not per-recipient). Used by `BoundariesMRF.filter/2` (`opts[:resolved][:allowlisted_by_user]`).
  """
  def allowlisted_by_users_subset(subjects, user_ids)
      when is_list(subjects) and is_list(user_ids) do
    user_ids
    |> Enum.map(&uid/1)
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Map.new(fn user_id ->
      {user_id,
       Circles.encircled_subset(
         subjects,
         Circles.stereotype_circle_ids_for(user_id, @stereotypes)
       )}
    end)
  end

  @doc "Add a subject to an allowlist: the acting `current_user`'s own, or with `scope: :instance_wide` the instance's, which takes `:configure` on the instance. A caller with nobody acting is refused unless it names a system path with `skip_boundary_check: true`. A user struct given instead of `opts` acts for themselves."
  def allow(subject, opts \\ []) do
    opts = allowlist_opts(opts)

    with :ok <- check_may_change_allowlist(opts),
         circles when circles != [] <- allow_circles(opts),
         done when is_list(done) <-
           Circles.add_to_circles(subject, circles, skip_boundary_check: true) do
      {:ok, "Allowlisted"}
    else
      {:error, :not_permitted} = refused -> refused
      _ -> {:error, "Could not add to allowlist"}
    end
  end

  @doc "Remove a subject from an allowlist. Takes the same `opts` as `allow/2`."
  def unallow(subject, opts \\ []) do
    opts = allowlist_opts(opts)

    with :ok <- check_may_change_allowlist(opts),
         circles when circles != [] <- allow_circles(opts),
         {removed, _} when is_integer(removed) <-
           Circles.remove_from_circles(subject, circles, skip_boundary_check: true) do
      {:ok, "Removed from allowlist"}
    else
      {:error, :not_permitted} = refused -> refused
      _ -> {:error, "Could not remove from allowlist"}
    end
  end

  defp allowlist_opts(opts) when is_list(opts), do: opts
  defp allowlist_opts(nil), do: []
  defp allowlist_opts(user) when is_map(user), do: [current_user: user]
  defp allowlist_opts(_), do: []

  # The server decides whose list it is: the acting user's own, or the instance's with `:configure` on the instance. Nobody acting is not "system", since a guest has no user either, so only `skip_boundary_check: true` is
  defp check_may_change_allowlist(opts) do
    user = current_user(opts)

    cond do
      Keyword.get(opts, :skip_boundary_check) == true ->
        :ok

      is_nil(user) ->
        error(:not_permitted, "Changing an allowlist needs a user acting, or skip_boundary_check")

      Keyword.get(opts, :scope) == :instance_wide and
          not Bonfire.Boundaries.can?(user, :configure, :instance) ->
        error(
          :not_permitted,
          "Only someone who may configure the instance can change its allowlist"
        )

      true ->
        :ok
    end
  end

  @doc "List subjects in allowlist circles for the given scope."
  def list(:instance_wide) do
    Circles.ids_for_stereotypes(@stereotypes)
    |> Circles.list_by_ids()
    |> repo().maybe_preload(encircles: [:peer, subject: [:profile, :character]])
  end

  def list(opts) do
    Circles.stereotype_circles_for(current_user(opts), @stereotypes)
    |> repo().maybe_preload(encircles: [:peer, subject: [:profile, :character]])
  end

  @doc "The allowlist circle for the given scope (there is only one `#{inspect(@stereotypes)}` circle per scope), or nil if it doesn't exist yet."
  def circle(scope) do
    list(scope)
    |> List.wrap()
    |> List.first()
  end

  @doc "The members (people and instances) of the allowlist for the given scope. `opts` are passed to `Circles.list_members/2`."
  def list_members(scope, opts \\ []) do
    case circle(scope) do
      nil -> []
      # every member: an allowlist is enforced, not shown
      circle -> Circles.list_members(circle, Keyword.put_new(opts, :skip_boundary_check, true))
    end
  end

  ###

  defp is_allowlisted_by?(subject, user_ids) when is_list(user_ids) and user_ids != [] do
    user_ids
    |> Enum.flat_map(&Circles.stereotype_circle_ids_for(uid(&1), @stereotypes))
    |> debug("per-user allow_them circle IDs")
    |> Circles.is_encircled_by?(subject, ...)
  end

  defp is_allowlisted_by?(subject, user_id) when is_binary(user_id),
    do: is_allowlisted_by?(subject, [user_id])

  defp is_allowlisted_by?(subject, %{} = user) when not is_nil(subject),
    do: is_allowlisted_by?(subject, [user])

  defp is_allowlisted_by?(_, _) do
    debug("no user provided for per-user allowlist check")
    false
  end

  defp allow_circles(opts) do
    if Keyword.get(opts, :scope) == :instance_wide,
      do: Circles.ids_for_stereotypes(@stereotypes),
      else: get_or_create_allow_circles(current_user(opts))
  end

  defp get_or_create_allow_circles(nil), do: []

  defp get_or_create_allow_circles(user) do
    @stereotypes
    |> Enum.map(&Circles.get_or_create_stereotype_circle(user, &1))
    |> Enum.flat_map(fn
      {:ok, circle} -> [circle]
      _ -> []
    end)
  end
end
