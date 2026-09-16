defmodule Bonfire.Boundaries.ConfigCheckTest do
  @moduledoc """
  Boot-time invariants for the boundary preset configuration. If any of these fail, the assertion message names exactly which config key and slug is at fault.
  """

  use ExUnit.Case, async: true

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag the extension case templates apply, so without it this also runs in the federation job catch-all
  @moduletag :backend

  alias Bonfire.Boundaries.ConfigCheck

  test "preset configuration is internally consistent" do
    assert :ok = ConfigCheck.validate!()
  end

  test "every group preset's declared dim slugs resolve in :preset_dimensions" do
    case ConfigCheck.report().preset_dims_resolve do
      :ok -> :ok
      {:error, violations} -> flunk(Enum.join(violations, "\n"))
    end
  end

  test "every dim slug has an ACL signature or is documented as circle-controlled" do
    case ConfigCheck.report().dim_slugs_have_acls do
      :ok -> :ok
      {:error, violations} -> flunk(Enum.join(violations, "\n"))
    end
  end

  test "no ACL atom is claimed by more than one dim in :group_dim_acls" do
    case ConfigCheck.report().no_cross_dim_acl_collision do
      :ok -> :ok
      {:error, violations} -> flunk(Enum.join(violations, "\n"))
    end
  end

  test "every *_interact ACL grants :follow to its stereotype subjects" do
    case ConfigCheck.report().interact_acls_grant_follow do
      :ok -> :ok
      {:error, violations} -> flunk(Enum.join(violations, "\n"))
    end
  end

  # The reverse of "every dim slug has an ACL signature": a `:preset_acls` entry nothing offers reads like a working slug to anyone editing the config, and would be taken for an ACL id if a caller ever passed it.
  test "every :preset_acls entry is offered by a dimension or declared as not being" do
    case ConfigCheck.report().acls_are_offered_or_declared do
      :ok -> :ok
      {:error, violations} -> flunk(Enum.join(violations, "\n"))
    end
  end

  test "no two slugs in one dimension share an ACL signature" do
    case ConfigCheck.report().no_duplicate_signatures_within_dim do
      :ok -> :ok
      {:error, violations} -> flunk(Enum.join(violations, "\n"))
    end
  end

  test "every visibility and content-default slug declares how much access it grants" do
    case ConfigCheck.report().grid_slugs_have_a_role do
      :ok -> :ok
      {:error, violations} -> flunk(Enum.join(violations, "\n"))
    end
  end

  test "a slug offered by both grid dimensions means the same thing in each" do
    case ConfigCheck.report().shared_slugs_agree_on_role do
      :ok -> :ok
      {:error, violations} -> flunk(Enum.join(violations, "\n"))
    end
  end

  test "every membership slug says what joining it means" do
    case ConfigCheck.report().membership_slugs_have_a_join_mode do
      :ok -> :ok
      {:error, violations} -> flunk(Enum.join(violations, "\n"))
    end
  end
end
