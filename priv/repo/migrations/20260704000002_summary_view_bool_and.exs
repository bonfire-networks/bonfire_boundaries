defmodule Bonfire.Boundaries.Repo.Migrations.SummaryViewBoolAnd do
  @moduledoc """
  Re-apply the `bonfire_boundaries_summary` view (`create or replace`) to pick up the
  `bool_and` aggregate swap in `Bonfire.Boundaries.Summary` (same NULL-skipping-AND
  semantics as the plpgsql `agg_perms`, ~2× faster measured; the agg_perms/add_perms
  functions are kept for compatibility).
  """
  use Ecto.Migration

  def up, do: Bonfire.Boundaries.Summary.migrate_views()

  # replacing a view isn't meaningfully reversible (and migrate_views/0 in the down
  # direction would DROP it) — rollback keeps the current definition
  def down, do: :ok
end
