defmodule Bonfire.Boundaries.DefaultBoundariesPresetNameTest do
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries.Presets
  alias Bonfire.Common.Settings
  import Bonfire.Me.Fake

  # Regression: when the user's default boundary is a custom preset / ACL, the
  # setting stores the ACL id. `default_boundaries/1` must resolve the id back to
  # the ACL's human-readable name (from the preloaded `my_acls` tuple-list) so the
  # composer button shows e.g. "Follows" instead of the raw ULID.

  test "resolves a custom ACL id to its name from my_acls" do
    acl_id = "01KTZTBQ5PWE212CGGATXJ57FJ"

    user =
      current_user(
        Settings.put([:bonfire_boundaries, :default_boundary_preset], acl_id,
          current_user: fake_user!()
        )
      )

    my_acls = [{acl_id, %{id: acl_id, name: "My Preset", field: :to_boundaries}}]

    assert [{^acl_id, "My Preset"}] =
             Presets.default_boundaries(current_user: user, my_acls: my_acls)
  end

  test "falls back to the id when the ACL is not in my_acls" do
    acl_id = "01KTZTBQ5PWE212CGGATXJ57FJ"

    user =
      current_user(
        Settings.put([:bonfire_boundaries, :default_boundary_preset], acl_id,
          current_user: fake_user!()
        )
      )

    assert [{^acl_id, ^acl_id}] =
             Presets.default_boundaries(current_user: user, my_acls: [])
  end

  test "still resolves built-in presets to their tuple" do
    user =
      current_user(
        Settings.put([:bonfire_boundaries, :default_boundary_preset], "local",
          current_user: fake_user!()
        )
      )

    assert [{"local", _}] = Presets.default_boundaries(current_user: user)
  end
end
