defmodule Bonfire.Boundaries.Repo.Migrations.RemoteBlocksTakeEffect do
  use Ecto.Migration

  def up do
    Bonfire.Boundaries.Scaffold.RemoteBlocksDataMigration.up()
  end

  def down, do: :ok
end
