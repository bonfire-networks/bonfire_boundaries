defmodule Bonfire.Boundaries.RequestBeforeFollowTest do
  @moduledoc """
  An account that reviews follows says so by withholding `:follow` and granting `:request`, rather than by carrying a negative grant.

  `no_follow` exists only because `:follow` is bundled into `verbs_interaction`, so every role from `interact` up hands it out and the restriction can only be expressed by taking it back. Giving `:follow` one home (`everyone_may_follow`) makes `request_before_follow` "grant the asking instead of the following", the same positive-only rule as the rest of the boundary presets, and leaves `no_follow` with no caller.

  What the account can DO is unchanged, which is the point of the pair below: the behaviour assertions must hold before and after, and only the mechanism changes.
  """
  use Bonfire.Boundaries.DataCase, async: false
  use Bonfire.Common.Utils
  @moduletag :backend

  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Controlleds
  alias Bonfire.Boundaries.Queries
  alias Bonfire.Me.Fake

  setup do
    # nothing here federates; applying boundaries otherwise spawns federation tasks with no DB ownership in tests
    Process.put(:federating, false)
    :ok
  end

  defp acl_ids_on(object) do
    Controlleds.list_acls_on_object(object)
    |> Enum.map(&(e(&1, :acl_id, nil) || e(&1, :acl, :id, nil)))
    |> Enum.reject(&is_nil/1)
  end

  describe "an account that reviews follows" do
    test "withholds following and permits asking" do
      followed = Fake.fake_user!(%{}, %{}, request_before_follow: true)
      asker = Fake.fake_user!()

      verbs = Queries.permitted_verbs_on(asker, followed, [:follow, :request])

      refute :follow in verbs, "following outright is what such an account holds back"
      assert :request in verbs, "asking is what it offers instead"
    end

    test "an ordinary account permits following directly" do
      followed = Fake.fake_user!()
      follower = Fake.fake_user!()

      assert :follow in Queries.permitted_verbs_on(follower, followed, [:follow]),
             "the control: following is granted by default, so the refusal above is about this account's choice rather than about follows being denied everywhere"
    end

    test "expresses it without a negative grant" do
      followed = Fake.fake_user!(%{}, %{}, request_before_follow: true)

      refute Acls.get_id!(:no_follow) in acl_ids_on(followed),
             "the restriction has to be a grant withheld rather than a denial added, or `:follow` cannot leave `verbs_interaction` and every role from `interact` up keeps handing it out"
    end
  end
end
