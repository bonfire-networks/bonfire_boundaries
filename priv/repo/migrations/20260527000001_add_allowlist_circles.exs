defmodule Bonfire.Boundaries.Repo.Migrations.AddAllowlistCircles do
  @moduledoc false
  use Ecto.Migration

  def up, do: Bonfire.Boundaries.Scaffold.Instance.upsert_circles()
  def down, do: nil
end
