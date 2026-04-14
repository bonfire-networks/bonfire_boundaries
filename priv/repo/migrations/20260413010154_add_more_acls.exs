defmodule Bonfire.Boundaries.Repo.Migrations.MoreAcls2Fixtures do
  @moduledoc false
  use Ecto.Migration

  import Bonfire.Boundaries.Scaffold

  def up, do: Bonfire.Boundaries.Scaffold.Instance.upsert_acls()
  def down, do: nil
end
