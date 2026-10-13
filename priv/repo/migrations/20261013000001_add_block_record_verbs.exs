defmodule Bonfire.Boundaries.Repo.Migrations.AddBlockRecordVerbs do
  @moduledoc false
  use Ecto.Migration

  # the `silence`, `ghost` and `hide` verbs a `Moderation` record of a block or hide is written with
  def up, do: Bonfire.Boundaries.Scaffold.Instance.upsert_verbs()
  def down, do: nil
end
