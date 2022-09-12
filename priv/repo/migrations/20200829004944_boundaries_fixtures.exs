defmodule Bonfire.Boundaries.Repo.Migrations.BoundariesFixtures do
  use Ecto.Migration

  import Bonfire.Boundaries.Fixtures

  def up, do: Bonfire.Boundaries.Fixtures.insert()
end
