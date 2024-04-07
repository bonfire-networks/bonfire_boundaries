defmodule Bonfire.Boundaries.Repo.Migrations.MoreVerbsFixturesUp do
  @moduledoc false
  use Ecto.Migration

  import Bonfire.Boundaries.Fixtures

  def up, do: Bonfire.Boundaries.Fixtures.upsert_verbs()
  def down, do: nil
end
