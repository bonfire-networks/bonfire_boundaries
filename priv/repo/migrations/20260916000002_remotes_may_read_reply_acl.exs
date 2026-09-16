defmodule Bonfire.Boundaries.Repo.Migrations.RemotesMayReadReplyAcl do
  @moduledoc false
  use Ecto.Migration

  # Creates the `remotes_may_read_reply` ACL and its grants. It is the remote twin of `locals_may_read_reply`, and the `unlisted` signature now names both: someone who can read an unlisted thing can reply to, mention and message it, whichever side of the wire they are on.
  #
  # Declaring an ACL in config is not enough for it to grant anything, without a row and its grants it silently permits nothing, which is what `AclFixturesTest` checks for. `upsert_acls/0` inserts every current ACL and re-upserts the grants, so this also picks up anything else config gained since the last such migration.
  def up, do: Bonfire.Boundaries.Scaffold.Instance.upsert_acls()
  def down, do: nil
end
