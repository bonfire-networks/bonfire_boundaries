defmodule Bonfire.Boundaries.Repo.Migrations.AddLocalsMayReadReplyAcl do
  @moduledoc false
  use Ecto.Migration

  import Bonfire.Boundaries.Scaffold

  # Seeds the new `:locals_may_read_reply` stereotype ACL (+ its grants) used by the
  # readable-but-low-reach tiers (unlisted/quiet) so locals can reply without boosting.
  def up, do: Bonfire.Boundaries.Scaffold.Instance.upsert_acls()
  def down, do: nil
end
