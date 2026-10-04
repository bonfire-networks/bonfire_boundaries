defmodule Bonfire.Boundaries.Repo.Migrations.MoreAcls2Fixtures do
  @moduledoc false
  use Ecto.Migration

  import Bonfire.Boundaries.Scaffold

  def up, do: Bonfire.Boundaries.Scaffold.Instance.upsert_verbs_acls_and_grants()
  def down, do: nil
end
