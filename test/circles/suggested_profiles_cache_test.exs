defmodule Bonfire.Boundaries.Circles.SuggestedProfilesCacheTest do
  @moduledoc """
  bonfire-app#2069: the curated suggested-profiles list is cached (6h), so profiles an admin adds
  at `settings/instance/suggested_profiles` don't appear until the TTL expires. The cached loader
  lives in the `Bonfire.Boundaries.Circles` context (shared by the "Who to follow" widget and the
  Masto `/api/v2/suggestions` endpoint); the standard `cache: :reset`/`:refresh` opt busts the cache
  so the widget's manual "refresh" reflects edits immediately.
  """
  use Bonfire.Boundaries.DataCase, async: false

  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Scaffold.Instance
  import Bonfire.Me.Fake

  setup do
    # start each test from a clean cache so a prior test's curated list doesn't leak
    Circles.list_suggested_profiles(cache: :reset)
    on_exit(fn -> Circles.list_suggested_profiles(cache: :reset) end)
    :ok
  end

  defp suggested_ids, do: Circles.list_suggested_profiles() |> Enum.map(&id/1)

  test "lists the members of the suggested-profiles circle" do
    user = fake_user!()
    {:ok, _} = Circles.add_to_circles(user, Instance.suggested_profiles_circle())

    assert user.id in suggested_ids()
  end

  test "the list is cached, and reset/0 busts it so an edit shows immediately" do
    a = fake_user!()
    {:ok, _} = Circles.add_to_circles(a, Instance.suggested_profiles_circle())

    # warm the cache
    assert a.id in suggested_ids()

    # an admin adds a second member AFTER the list was cached
    b = fake_user!()
    {:ok, _} = Circles.add_to_circles(b, Instance.suggested_profiles_circle())

    # still serving the stale cached list — this is the #2069 symptom
    refute b.id in suggested_ids()

    # the reset (what the widget's refresh button calls) busts the cache
    Circles.list_suggested_profiles(cache: :reset)

    assert b.id in suggested_ids()
  end
end
