defmodule Bonfire.Boundaries.CanOrUnloadedTest do
  @moduledoc """
  Unit tests for `Bonfire.Boundaries.can_or_unloaded?/3` — the optimistic
  permission helper used by per-activity action button templates (boost, like,
  reply, quote) to avoid n+1 verb-permission DB queries when the surrounding
  `update_many` boundary preload hasn't completed.
  """

  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries
  alias Bonfire.Me.Fake

  describe "can_or_unloaded?/3" do
    test "returns true (optimistic) when there is no current user" do
      assert Boundaries.can_or_unloaded?(%{}, :like, nil)
      assert Boundaries.can_or_unloaded?(%{current_user: nil}, :boost, %{verbs: [], value: true})
    end

    test "returns true when object_boundary is nil" do
      user = Fake.fake_user!()
      assert Boundaries.can_or_unloaded?(%{current_user: user}, :like, nil)
    end

    test "returns true when object_boundary is :skip_boundary_preload" do
      user = Fake.fake_user!()

      assert Boundaries.can_or_unloaded?(
               %{current_user: user},
               :like,
               :skip_boundary_preload
             )
    end

    test "delegates to can?/3 (returns true) when boundary is preloaded and verb is granted" do
      user = Fake.fake_user!()
      # Boundary fast-path expects %{verbs: [..verb names..], value: true}
      boundary = %{verbs: ["Like", "Read", "See"], value: true}

      assert Boundaries.can_or_unloaded?(%{current_user: user}, :like, boundary)
    end

    test "delegates to can?/3 (returns false) when boundary is preloaded and verb is missing" do
      user = Fake.fake_user!()
      boundary = %{verbs: ["Read", "See"], value: true}

      refute Boundaries.can_or_unloaded?(%{current_user: user}, :like, boundary)
    end

    test "passes through a verb list to can?/3" do
      # `can?/3` accepts either a single verb atom or a list. Templates that
      # check multiple verbs at once (e.g. `can?(ctx, [:see, :read], boundary)`)
      # must still benefit from the same in-memory fast path.
      user = Fake.fake_user!()
      boundary = %{verbs: ["Like", "Read", "See"], value: true}

      assert Boundaries.can_or_unloaded?(%{current_user: user}, [:like, :read], boundary)
      refute Boundaries.can_or_unloaded?(%{current_user: user}, [:like, :boost], boundary)
    end

    test "with `value: false` boundary, falls through to can?/3 slow path" do
      # The fast path at `boundaries.ex:367` only matches `value: true`. A
      # `value: false` boundary (explicit denial) does NOT match the fast
      # path and falls through to the DB-querying clause via
      # `pointer_permitted?`. If you see this shape flowing through
      # templates and triggering n+1 queries, add an explicit short-circuit
      # for `value: false` to `can_or_unloaded?/3`.
      user = Fake.fake_user!()
      boundary = %{verbs: [], value: false}

      refute Boundaries.can_or_unloaded?(%{current_user: user}, :like, boundary)
    end
  end
end
