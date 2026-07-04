defmodule Bonfire.Boundaries.Repo.Migrations.AddGrantDenyPartialIndex do
  @moduledoc """
  Partial index over only the negative grants (`value = false`), see `Bonfire.Data.AccessControl.Grant.Migration.add_grant_deny_index/0`. Ships ahead of the direct EXISTS/NOT-EXISTS boundary-check rewrite, whose deny probe it serves.
  """
  use Ecto.Migration
  use Needle.Migration.Indexable

  def up do
    Bonfire.Data.AccessControl.Grant.Migration.add_grant_deny_index()
  end

  def down do
    Bonfire.Data.AccessControl.Grant.Migration.drop_grant_deny_index()
  end
end