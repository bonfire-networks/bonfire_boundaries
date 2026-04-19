defmodule Bonfire.Boundaries.Repo.Migrations.RemoveDuplicateLocalsMayReadInteract do
  @moduledoc false
  use Ecto.Migration

  def up do
    # Remove the duplicate locals_may_read_interact ACL (id: "10CA1SMAYREAD1NTERACTYYYYY")
    # that was added alongside the original "10CA1SMAYSEEANDREAD0N1YN0W".
    # The original is kept; this duplicate had no grants and caused slug detection collisions.
    execute("DELETE FROM bonfire_data_access_control_acl WHERE id = '10CA1SMAYREAD1NTERACTYYYYY'")
  end

  def down, do: nil
end
