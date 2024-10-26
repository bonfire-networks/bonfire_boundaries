defmodule Bonfire.Boundaries.Summary do
  @moduledoc """
  View that facilities the querying of objects' boundaries. See `Bonfire.Boundaries.Queries` for how it is used.
  """

  # Version of the view (not used at the moment). Could be incremented when making changes to the view and writing a new migration, including dropping the previous version.
  @version 1

  # Base name of the table/view
  @table_base_name "bonfire_boundaries_summary"

  # Configure the view type, eg. regular (default) or materialized (experimental)
  @view_type "view"
  @create_view_type "or replace view"
  # @view_type "MATERIALIZED view"
  # @create_view_type @view_type

  use Ecto.Schema
  import Ecto.Query

  use EctoVista,
    table_name: @table_base_name,
    version: @version,
    repo: Bonfire.Common.Repo

  use Untangle

  alias Needle.Pointer
  alias Needle.ULID
  alias Bonfire.Data.AccessControl.Circle
  alias Bonfire.Data.AccessControl.Controlled
  alias Bonfire.Data.AccessControl.Encircle
  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.AccessControl.Verb

  # Storing the table names for later use
  @circle_table Circle.__schema__(:source)
  @controlled_table Controlled.__schema__(:source)
  @encircle_table Encircle.__schema__(:source)
  @grant_table Grant.__schema__(:source)
  @pointer_table Pointer.__schema__(:source)
  @verb_table Verb.__schema__(:source)

  @primary_key false
  @foreign_key_type ULID
  schema @table_base_name do
    belongs_to(:subject, Pointer, primary_key: true)
    belongs_to(:object, Pointer, primary_key: true)
    belongs_to(:verb, Verb, primary_key: true)
    field(:value, :boolean)
  end

  @doc """
  Creates a custom SQL function to add two boolean values.

  If either input is `nil`, the function returns the other value.
  Otherwise, it returns the logical AND of the two input values.
  """
  @create_add_perms """
  create or replace function add_perms(bool, bool)
  returns bool as $$
  begin
    if $1 is null then return $2; end if;
    if $2 is null then return $1; end if;
    return ($1 and $2);
  end;
  $$ language plpgsql
  """

  @doc """
  Creates a custom SQL aggregate function to aggregate boolean values using the `add_perms` function.
  """
  @create_agg_perms """
  create or replace aggregate agg_perms(bool) (
    sfunc = add_perms,
    stype = bool,
    combinefunc = add_perms,
    parallel = safe
  )
  """

  @drop_add_perms "drop function add_perms(bool, bool)"
  @drop_agg_perms "drop aggregate agg_perms(bool)"

  @doc """
  Migrates the custom SQL functions for permission calculation.

  This function executes the creation or dropping of the `add_perms` and `agg_perms` functions.
  """
  def migrate_functions do
    # This has the appearance of being muddled, but it's intentional.
    Ecto.Migration.execute(@create_add_perms, @drop_agg_perms)
    Ecto.Migration.execute(@create_agg_perms, @drop_add_perms)
  end

  @doc """
  SQL query to create the summary view.

  The view aggregates the permissions for each subject, object, and verb combination by performing a complex join operation across several tables.
  """
  @create_summary_view """
  create #{@create_view_type} #{@table_base_name} as
  select
    pointer.id         as subject_id,
    controlled.id      as object_id,
    verb.id            as verb_id,
    agg_perms(g.value) as value
  from
    "#{@pointer_table}" pointer
    cross join "#{@controlled_table}" controlled
    cross join "#{@verb_table}" verb
    left join "#{@grant_table}" g
      on  controlled.acl_id = g.acl_id
      and g.verb_id = verb.id
    left join "#{@circle_table}" circle
      on g.subject_id = circle.id
    left join "#{@encircle_table}" encircle
      on  encircle.circle_id  = circle.id
      and encircle.subject_id = pointer.id
  where g.subject_id = pointer.id or encircle.id is not null
  group by (pointer.id, controlled.id, verb.id)
  """

  @doc "An equivalent of the Summary view, but represented as an Ecto subquery instead"
  def base_summary_query do
    subquery(
      from(pointer in Pointer,
        cross_join: controlled in Controlled,
        cross_join: verb in Verb,
        left_join: g in Grant,
        on:
          controlled.acl_id == g.acl_id and
            g.verb_id == verb.id,
        left_join: circle in Circle,
        on: g.subject_id == circle.id,
        left_join: encircle in Encircle,
        on:
          encircle.circle_id == circle.id and
            encircle.subject_id == pointer.id,
        where: g.subject_id == pointer.id or not is_nil(encircle.id),
        group_by: [pointer.id, controlled.id, verb.id],
        select: %{
          subject_id: pointer.id,
          object_id: controlled.id,
          verb_id: verb.id,
          value: fragment("agg_perms(?)", g.value)
        }
      )
    )
  end

  @doc """
  Generates the SQL to drop the view.

  The `view_type` parameter can be used to specify the type of view (eg. regular or materialized).
  """
  defp drop_view_sql(view_type \\ @view_type) do
    "drop #{view_type} if exists #{@table_base_name}"
  end

  @doc """
  Executes the dropping of views for the given `view_type`.
  """
  def drop_views(view_type \\ @view_type) do
    Ecto.Migration.execute(drop_view_sql(view_type))
  end

  @doc """
  Migrates the summary view.

  This function creates the summary view using the `@create_summary_view` SQL query, or drops it in down migrations.
  """
  @decorate time()
  def migrate_views do
    Ecto.Migration.execute(@create_summary_view, drop_view_sql())
  end

  @doc """
  Refreshes the materialized view.

  This function is used to refresh the materialized view (only use if the view is materialized).
  """
  @decorate time()
  def refresh_material_view do
    @table_base_name
    |> refresh_query()
    |> repo().query()
    |> handle_refresh_result()
  end

  @doc """
  Migrates the module up.

  This function handles the migration process for the up direction. It calls the `migrate_functions/0` and `migrate_views/0` functions.
  """
  def migrate(:up) do
    migrate_functions()
    migrate_views()

    # Ecto.Migration.execute("drop view if exists #{@table_base_name}_#{@version-1}") 
    # ^ to drop previous version (after new one was created)
  end

  @doc """
  Migrates the module down.

  This function handles the migration process for the down direction. It calls `migrate_views/0` and `migrate_functions/0`.
  """
  def migrate(:down) do
    migrate_views()
    # Ecto.Migration.execute("drop view if exists #{@table_base_name}_#{@version-1}")
    migrate_functions()
  end
end
