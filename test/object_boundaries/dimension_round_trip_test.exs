if Bonfire.Common.Extend.extension_enabled?(:bonfire_classify) do
  defmodule Bonfire.Boundaries.DimensionRoundTripTest do
    @moduledoc """
    A group's dimensions are not stored, they are DERIVED from the ACLs on the object, so every slug has to survive the trip out and back.

    The invariant is about false positives rather than about completeness: applying slug S and reading it back gives S, or `nil`, never a DIFFERENT slug. `nil` is sometimes returned since detection works by matching ACL signatures and several slugs deliberately have none (their access is circle-granted). A different slug should not be returned: it reports a rule the group was never given, and everything downstream believes it, including `actor_declarations/2`, which turns it into a claim to other servers.

    `preset_round_trip_test.exs` covers the same ground for the configured preset COMBINATIONS. This covers each slug on its own, so a slug no preset happens to use is still checked.
    """
    use Bonfire.Boundaries.DataCase, async: false

    alias Bonfire.Boundaries.Presets
    alias Bonfire.Classify.Boundaries

    import Bonfire.Classify.Simulate
    import Bonfire.Me.Fake

    @moduletag :backend

    # The three dimensions `group_dimension_slugs/1` reports. `default_content_visibility` is not
    # among them: it is stored in settings rather than derived, and is covered separately below.
    @detected_dims [:membership, :visibility, :participation]

    setup do
      Process.put(:federating, false)
      %{me: fake_user!()}
    end

    # Applies every slug of every detected dimension and records what came back, so the two tests below can assert on the whole picture rather than stopping at the first surprise.
    defp detect_all(me) do
      for dim <- @detected_dims, slug <- Presets.dimension_slug_order(dim) do
        group = fake_group!(me)
        assert :ok = Boundaries.replace(group, me, %{dim => slug})
        {dim, slug, Presets.group_dimension_slugs(group)[dim]}
      end
    end

    test "no slug reads back as a different slug", %{me: me} do
      false_positives =
        for {dim, slug, detected} <- detect_all(me),
            not is_nil(detected),
            detected != slug,
            do: {dim, slug, detected}

      assert false_positives == [],
             "a slug reading back as a DIFFERENT one reports a rule the group was never given, and everything downstream believes it, including `actor_declarations/2`, which states it to other servers"
    end

    # Pinned separately because `nil` is honest but not free: whatever asks the group its rules gets `resolve_dims/1`'s default in place of an answer. A slug joining this set is a decision, so it should have to be written down here.
    test "which slugs are undetectable, so a change to that set is deliberate", %{me: me} do
      undetectable =
        for {dim, slug, detected} <- detect_all(me), is_nil(detected), do: {dim, slug}

      assert undetectable == [{:visibility, "members:private"}],
             "members-only grants nothing globally, so it has no ACL signature to match, but every other slug must be detectable"
    end

    # Stored rather than derived, so it round-trips through its own reader. `read_default_content_visibility/2` also falls back to the parent group, which is why this asserts on a group rather than a topic.
    test "every content-default slug reads back as itself", %{me: me} do
      for slug <- Presets.dimension_slug_order(:default_content_visibility) do
        group = fake_group!(me)
        assert :ok = Boundaries.replace(group, me, %{default_content_visibility: slug})

        group = repo().maybe_preload(group, :settings, force: true)

        assert Boundaries.read_default_content_visibility(group) == slug
      end
    end
  end
end
