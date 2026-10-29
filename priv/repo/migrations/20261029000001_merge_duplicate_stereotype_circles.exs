defmodule Bonfire.Boundaries.Repo.Migrations.MergeDuplicateStereotypeCircles do
  use Ecto.Migration

  def up do
    Bonfire.Boundaries.Scaffold.DuplicateStereotypeCirclesDataMigration.up()
  end

  def down, do: :ok
end
