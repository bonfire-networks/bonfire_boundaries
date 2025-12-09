defmodule Bonfire.Boundaries.Repo.Migrations.MoreCircles4Fixtures do
  @moduledoc false
  use Ecto.Migration

  import Bonfire.Boundaries.Scaffold

  def up, do: Bonfire.Boundaries.Scaffold.Instance.upsert_circles()
  def down, do: nil
end
