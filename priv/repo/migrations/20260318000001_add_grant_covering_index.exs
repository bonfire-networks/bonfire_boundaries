defmodule Bonfire.Boundaries.Repo.Migrations.AddGrantCoveringIndex do
  @moduledoc false
  use Ecto.Migration
  use Needle.Migration.Indexable

  def up do
    Bonfire.Data.AccessControl.Grant.Migration.add_grant_covering_index()

    execute "ALTER TABLE bonfire_data_access_control_grant SET (autovacuum_analyze_scale_factor = 0.01)"
    execute "ALTER TABLE bonfire_data_access_control_controlled SET (autovacuum_analyze_scale_factor = 0.01)"
    execute "ALTER TABLE pointers_pointer SET (autovacuum_analyze_scale_factor = 0.01)"
  end

  def down do
    Bonfire.Data.AccessControl.Grant.Migration.drop_grant_covering_index()

    execute "ALTER TABLE bonfire_data_access_control_grant RESET (autovacuum_analyze_scale_factor)"
    execute "ALTER TABLE bonfire_data_access_control_controlled RESET (autovacuum_analyze_scale_factor)"
    execute "ALTER TABLE pointers_pointer RESET (autovacuum_analyze_scale_factor)"
  end
end
