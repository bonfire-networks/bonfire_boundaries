defmodule Bonfire.Boundaries.Repo.Migrations.BoundariesFixturesUp do
  @moduledoc false
  use Ecto.Migration

  import Bonfire.Boundaries.Scaffold

  def up, do: Bonfire.Boundaries.Scaffold.insert()
  def down, do: nil
end
