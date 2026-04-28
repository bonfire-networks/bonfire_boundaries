defmodule Bonfire.Boundaries.ConfigCheckTest do
  @moduledoc """
  Boot-time invariants for the boundary preset configuration. If any of these
  fail, the assertion message names exactly which config key and slug is at fault.
  """

  use ExUnit.Case, async: true

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
end
