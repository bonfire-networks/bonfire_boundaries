defmodule Bonfire.Boundaries.Repo.Migrations.AddMoreAcls3 do
  @moduledoc false
  use Ecto.Migration

  import Bonfire.Boundaries.Scaffold

  def up, do: Bonfire.Boundaries.Scaffold.Instance.upsert_acls()
  def down, do: nil
end
