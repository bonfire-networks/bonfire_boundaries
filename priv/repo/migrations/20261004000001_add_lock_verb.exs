defmodule Bonfire.Boundaries.Repo.Migrations.AddLockVerb do
  @moduledoc false
  use Ecto.Migration

  # the `lock` verb a `Moderation` record of a lock is written with
  def up, do: Bonfire.Boundaries.Scaffold.Instance.upsert_verbs()
  def down, do: nil
end
