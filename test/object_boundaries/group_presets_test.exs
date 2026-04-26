defmodule Bonfire.Boundaries.GroupPresetsTest do
  @moduledoc """
  Covers the helpers in `Bonfire.Boundaries.Presets` that resolve a group's audience
  preset + dimension slugs for display. The pure-config helpers are tested directly;
  the ACL-walking `group_dimension_slugs/1` and composed `group_row_chip/1` round-trip
  through `Bonfire.Classify.Simulate.fake_group!/2` to create real groups with known
  dimension slugs and verify the helpers read them back correctly.
  """

  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries.Presets
  alias Bonfire.Me.Fake
  alias Bonfire.Classify.Simulate

  setup do
    # Mirrors the classify tests' setup; federation is out of scope for group boundaries.
    Process.put(:federating, false)
    :ok
  end

  describe "preset_slug_from_dims/1" do
    test "matches the public_local_community preset" do
      assert "public_local_community" ==
               Presets.preset_slug_from_dims(%{
                 membership: "local:members",
                 visibility: "nonfederated",
                 participation: "group_members"
               })
    end

    test "matches the announcement_channel preset" do
      assert "announcement_channel" ==
               Presets.preset_slug_from_dims(%{
                 membership: "invite_only",
                 visibility: "nonfederated",
                 participation: "moderators"
               })
    end

    test "matches the private_club preset" do
      assert "private_club" ==
               Presets.preset_slug_from_dims(%{
                 membership: "on_request",
                 visibility: "local:discoverable",
                 participation: "group_members"
               })
    end

    test "returns nil when the combination does not match any configured preset" do
      refute Presets.preset_slug_from_dims(%{
               membership: "on_request",
               visibility: "nonfederated",
               participation: "local:contributors"
             })
    end

    test "returns nil for an empty dim map" do
      refute Presets.preset_slug_from_dims(%{})
    end

    test "returns nil when dims are all nil" do
      refute Presets.preset_slug_from_dims(%{
               membership: nil,
               visibility: nil,
               participation: nil
             })
    end
  end

  describe "group_preset_meta/1" do
    test "returns nil for nil slug" do
      refute Presets.group_preset_meta(nil)
    end

    test "returns nil for an unknown slug" do
      refute Presets.group_preset_meta("not_a_preset")
    end

    test "returns metadata for a known preset" do
      assert %{} = meta = Presets.group_preset_meta("private_club")
      assert meta[:membership] == "on_request"
      assert meta[:visibility] == "local:discoverable"
      assert meta[:participation] == "group_members"
      assert is_binary(meta[:icon])
    end
  end

  describe "dimension_meta/2" do
    test "returns nil for nil slug" do
      refute Presets.dimension_meta(:membership, nil)
    end

    test "returns nil for an unknown slug" do
      refute Presets.dimension_meta(:membership, "not_a_real_slug")
    end

    test "returns metadata for a known membership slug" do
      assert %{icon: "ph:hand-waving-duotone"} = Presets.dimension_meta(:membership, "on_request")
    end

    test "returns metadata for a known visibility slug" do
      assert %{icon: icon} = Presets.dimension_meta(:visibility, "local")
      assert is_binary(icon)
    end

    test "returns metadata for a known participation slug" do
      assert %{icon: icon} = Presets.dimension_meta(:participation, "group_members")
      assert is_binary(icon)
    end
  end

  describe "group_dimension_slugs/1" do
    test "derives the dims applied to a public_local_community-like group" do
      creator = Fake.fake_user!()

      group =
        Simulate.fake_group!(creator, %{
          membership: "local:members",
          visibility: "nonfederated",
          participation: "group_members"
        })

      assert %{
               membership: "local:members",
               visibility: "nonfederated",
               participation: "group_members"
             } = Presets.group_dimension_slugs(group)
    end

    test "derives the dims applied to a private_club-like group" do
      creator = Fake.fake_user!()

      group =
        Simulate.fake_group!(creator, %{
          membership: "on_request",
          visibility: "local:discoverable",
          participation: "group_members"
        })

      assert %{
               membership: "on_request",
               visibility: "local:discoverable",
               participation: "group_members"
             } = Presets.group_dimension_slugs(group)
    end

    test "falls back to invite_only when no membership ACL matches" do
      creator = Fake.fake_user!()

      # invite_only applies no ACL grants; the fallback in group_dimension_slugs should
      # still return "invite_only" (the most restrictive slug, matching the config default).
      group =
        Simulate.fake_group!(creator, %{
          membership: "invite_only",
          visibility: "nonfederated",
          participation: "moderators"
        })

      assert %{membership: "invite_only"} = Presets.group_dimension_slugs(group)
    end
  end

  describe "group_row_chip/1" do
    test "returns preset metadata when the group matches a known preset" do
      creator = Fake.fake_user!()

      group =
        Simulate.fake_group!(creator, %{
          membership: "local:members",
          visibility: "nonfederated",
          participation: "group_members"
        })

      chip = Presets.group_row_chip(group)
      assert is_map(chip)
      # Same three coordinates the public_local_community preset is built from:
      assert chip[:membership] == "local:members"
      assert chip[:visibility] == "nonfederated"
      assert chip[:participation] == "group_members"
    end

    test "falls back to the membership dimension meta for a custom dim combination" do
      creator = Fake.fake_user!()

      # on_request membership + nonfederated visibility + local:contributors participation
      # doesn't match any configured preset, so row_chip should return membership meta.
      group =
        Simulate.fake_group!(creator, %{
          membership: "on_request",
          visibility: "nonfederated",
          participation: "local:contributors"
        })

      assert %{icon: "ph:hand-waving-duotone"} = Presets.group_row_chip(group)
    end
  end
end
