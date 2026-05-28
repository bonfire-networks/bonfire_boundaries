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
    Circles.ids_for_stereotypes(@stereotypes)
    |> Circles.is_encircled_by?(subject, ...)
  end

  def is_allowlisted?(subject, opts) when not is_nil(subject) do
    is_allowlisted?(subject, :instance_wide) ||
      is_allowlisted_by?(
        subject,
        e(opts, :user_ids, nil) || current_user(opts)
      )
  end

  def is_allowlisted?(_, _) do
    warn("no subject provided to check")
    false
  end

  @doc "Add a subject to an allowlist. `scope` is `:instance_wide` or a user struct/id."
  def allow(subject, scope \\ :instance_wide) do
    with circles when circles != [] <- allow_circles(scope),
         done when is_list(done) <- Circles.add_to_circles(subject, circles) do
      {:ok, "Allowlisted"}
    else
      _ -> {:error, "Could not add to allowlist"}
    end
  end

  @doc "Remove a subject from an allowlist."
  def unallow(subject, scope \\ :instance_wide) do
    with circles when circles != [] <- allow_circles(scope),
         done when is_list(done) <- Circles.remove_from_circles(subject, circles) do
      {:ok, "Removed from allowlist"}
    else
      _ -> {:error, "Could not remove from allowlist"}
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

  defp allow_circles(:instance_wide), do: Circles.ids_for_stereotypes(@stereotypes)

  defp allow_circles(opts) when is_list(opts),
    do: get_or_create_allow_circles(current_user(opts))

  defp allow_circles(user), do: get_or_create_allow_circles(user)

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
