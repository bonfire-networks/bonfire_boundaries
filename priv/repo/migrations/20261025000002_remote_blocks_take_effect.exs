defmodule Bonfire.Boundaries.Repo.Migrations.RemoteBlocksTakeEffect do
  use Ecto.Migration

  def up do
    # the migration's own repo, so the scaffolding acts on the database being migrated
    EctoSparkles.DataMigration.Runner.run(
      Bonfire.Boundaries.Scaffold.RemoteBlocksDataMigration,
      repo: repo()
    )
  end

  def down, do: :ok
end
