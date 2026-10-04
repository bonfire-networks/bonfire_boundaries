defmodule Bonfire.Boundaries.Repo.Migrations.GroupAcls do
  @moduledoc false
  use Ecto.Migration

  # Creates the `group_mods_may_moderate` and `group_members_may_participate` stereotypes (declared by classify), which each group's own moderators and members ACLs are stereotyped as. A stereotype declared in config has no row until this runs, and a group's ACL cannot point at one that does not exist. `upsert_verbs_acls_and_grants/0` inserts every current ACL and re-upserts the grants, as `20260916000002_remotes_may_read_reply_acl.exs` does.
  def up, do: Bonfire.Boundaries.Scaffold.Instance.upsert_verbs_acls_and_grants()
  def down, do: nil
end
