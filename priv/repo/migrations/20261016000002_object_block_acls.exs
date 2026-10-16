defmodule Bonfire.Boundaries.Repo.Migrations.ObjectBlockAcls do
  @moduledoc false
  use Ecto.Migration

  # Creates the `locked` and `hidden` ACLs and their grants, and the `hidden_by_me` stereotype each person's own hide ACL is made from. Locking or hiding an object now attaches one of these instead of writing grants into the object's own ACL, where a lock and a hide overlapped.
  #
  # Declaring an ACL in config is not enough for it to grant anything, without a row and its grants it silently permits nothing. `upsert_verbs_acls_and_grants/0` inserts every current ACL and re-upserts the grants, so this also picks up anything else config gained since the last such migration.
  def up, do: Bonfire.Boundaries.Scaffold.Instance.upsert_verbs_acls_and_grants()
  def down, do: nil
end
