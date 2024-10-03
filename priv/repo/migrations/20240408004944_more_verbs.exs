defmodule Bonfire.Boundaries.Repo.Migrations.MoreVerbsFixturesUp do
  @moduledoc false
  use Ecto.Migration

  import Bonfire.Boundaries.Scaffold

  def up, do: Bonfire.Boundaries.Scaffold.Instance.upsert_verbs()
  def down, do: nil
end
