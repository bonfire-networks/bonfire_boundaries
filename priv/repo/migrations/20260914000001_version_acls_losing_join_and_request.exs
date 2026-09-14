defmodule Bonfire.Boundaries.Repo.Migrations.VersionAclsLosingJoinAndRequest do
  @moduledoc false
  use Ecto.Migration

  # Creates the new ids for the six ACLs whose verb sets shrank when `:request` left the read bundles and `:join` left `verbs_partake`.
  #
  # Grants are upserted and never pruned, so the rows under the OLD ids still grant both verbs. Rather than edit those rows, which are global fixtures shared by every object ever created against them, each ACL keeps its name and takes a new id while the old id lives on under a `*_join_request` / `*_request` name marked `deprecated`. Existing objects therefore keep exactly the permissions they had, and only groups get re-pointed, by a separate DataMigration.
  #
  # This inserts the new ACLs and their grants. Deprecated ACLs are skipped by `upsert_acls/0`, so nothing here recreates the old rows on an instance that never had them.
  def up, do: Bonfire.Boundaries.Scaffold.Instance.upsert_acls()
  def down, do: nil
end
