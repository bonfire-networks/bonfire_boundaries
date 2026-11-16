defmodule Bonfire.Boundaries.Repo.Migrations.MergeDuplicateStereotypeCircles do
  use Ecto.Migration

  def up do
    # the migration's own repo, so the merge acts on the database being migrated
    EctoSparkles.DataMigration.Runner.run(
      Bonfire.Boundaries.Scaffold.DuplicateStereotypeCirclesDataMigration,
      repo: repo()
    )
  end

  def down, do: :ok
end
