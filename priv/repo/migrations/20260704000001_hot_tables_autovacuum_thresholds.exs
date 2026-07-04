defmodule Bonfire.Boundaries.Repo.Migrations.HotTablesAutovacuumThresholds do
  @moduledoc """
  Per-table autovacuum thresholds for the hottest tables.

  Bonfire's workload is soft-delete + append: dead tuples never approach the default
  DELETE trigger (`autovacuum_vacuum_scale_factor` 0.2 = ~12M dead rows on a 60M-row
  grant table), and the INSERT trigger (also 20%) takes months of traffic — during which
  the cumulative statistics counters it depends on are wiped by any unclean shutdown.
  Net effect observed in production: `last_autovacuum` NULL on 14 of the top-15 tables,
  stale visibility maps defeating index-only scans (measured: 31.9M heap fetches on one
  feed query via `feed_publish`, dropping to 521 after a single VACUUM, feed 17.0s → 15.2s).

  `autovacuum_vacuum_insert_scale_factor = 0.01` is the key setting: vacuum after 1% fresh
  inserts keeps visibility maps healthy, and the low bar is re-crossable even after a
  stats wipe. `oban_jobs` is included because the Oban pruner's constant insert+delete
  churn bloats its indexes worst of all (observed: 5GB of indexes on a 99MB heap).

  These are table storage parameters: they need only table ownership (no superuser),
  apply on managed Postgres too, and take a brief SHARE UPDATE EXCLUSIVE lock (no rewrite).
  Tables are guarded with `to_regclass` so flavours/instances without a given table migrate cleanly.
  """
  use Ecto.Migration

  @hot_tables ~w(
    bonfire_data_access_control_grant
    bonfire_data_access_control_controlled
    bonfire_data_access_control_encircle
    pointers_pointer
    bonfire_data_social_replied
    bonfire_data_social_feed_publish
    bonfire_data_social_activity
    bonfire_data_identity_character
    bonfire_data_activity_pub_peered
    oban_jobs
  )

  @settings "autovacuum_vacuum_scale_factor = 0.02, autovacuum_vacuum_insert_scale_factor = 0.01, autovacuum_analyze_scale_factor = 0.01"
  @reset "autovacuum_vacuum_scale_factor, autovacuum_vacuum_insert_scale_factor, autovacuum_analyze_scale_factor"

  def up do
    for table <- @hot_tables do
      execute """
      DO $$ BEGIN
        IF to_regclass('#{table}') IS NOT NULL THEN
          EXECUTE 'ALTER TABLE #{table} SET (#{@settings})';
        END IF;
      END $$
      """
    end
  end

  def down do
    for table <- @hot_tables do
      execute """
      DO $$ BEGIN
        IF to_regclass('#{table}') IS NOT NULL THEN
          EXECUTE 'ALTER TABLE #{table} RESET (#{@reset})';
        END IF;
      END $$
      """
    end
  end
end
