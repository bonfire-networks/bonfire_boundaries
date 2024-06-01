defmodule Bonfire.Boundaries.Summary do
  @moduledoc "View that facilities the querying of objects' boundaries. See `Bonfire.Boundaries.Queries` for how it is used."
  @table_base_name "bonfire_boundaries_summary"
  # NOTE: not currently used, could increment this when making changes to the view (and writing a new migration, including dropping the previous version), in which case should use @table_name instead of @table_base_name
  @version 1

  use Ecto.Schema

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

  def migrate_functions do
    # this has the appearance of being muddled, but it's intentional.
    Ecto.Migration.execute(@create_add_perms, @drop_agg_perms)
    Ecto.Migration.execute(@create_agg_perms, @drop_add_perms)
  end

  @view_type "view"
  @create_view_type "or replace view"

  # @view_type "MATERIALIZED view"
  # @create_view_type @view_type

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

  defp drop_view_sql(view_type \\ @view_type) do
    "drop #{view_type} if exists #{@table_base_name}"
  end

  def drop_views(view_type \\ @view_type) do
    Ecto.Migration.execute(drop_view_sql(view_type))
  end

  @decorate time()
  def migrate_views do
    Ecto.Migration.execute(@create_summary_view, drop_view_sql())
  end

  @decorate time()
  def refresh_material_view do
    @table_base_name
    |> refresh_query()
    |> repo().query()
    |> handle_refresh_result()
  end

  def migrate(:up) do
    migrate_functions()
    migrate_views()

    # Ecto.Migration.execute("drop view if exists #{@table_base_name}_#{@version-1}") # drop previous version (after new one was created)
  end

  def migrate(:down) do
    migrate_views()
    # Ecto.Migration.execute("drop view if exists #{@table_base_name}_#{@version-1}")
    migrate_functions()
  end
end
