defmodule Bonfire.Boundaries.Migrations do

  alias Bonfire.Data.AccessControl.{Access, Acl, Circle, Controlled, Encircle, Grant}
  alias Pointers.Pointer

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

  @access_table     Access.__schema__(:source)
  @circle_table     Circle.__schema__(:source)
  @controlled_table Controlled.__schema__(:source)
  @encircle_table   Encircle.__schema__(:source)
  @grant_table      Grant.__schema__(:source)
  @pointer_table    Pointer.__schema__(:source)

  # e.g.
  # create or replace view boundaries_see_read as
  # select
  #   pointer.id    as subject_id,
  #   controlled.id as object_id,
  #   agg_perms(access.can_see)  as can_see,
  #   agg_perms(access.can_read) as can_read
  # from
  #   pointers_pointer pointer
  #   join bonfire_data_access_control_controlled controlled
  #     on true
  #   join bonfire_data_access_control_grant g
  #     on (controlled.acl_id = g.acl_id)
  #   join bonfire_data_access_control_access access
  #     on (g.access_id = access.id)
  #   left join bonfire_data_social_circle circle 
  #     on (g.subject_id = circle.id)
  #   left join bonfire_data_social_encircle encircle
  #     on (circle.id = encircle.circle_id
  #         and encircle.subject_id = pointer.id)
  # where (circle.id = pointer.id or encircle.id is not null)
  # group by (pointer.id, controlled.id, access.id)
  # ;

  @create_boundaries_see_read_view """
  create or replace view boundaries_see_read as
  select
    pointer.id    as subject_id,
    controlled.id as object_id,
    agg_perms(access.can_see)  as can_see,
    agg_perms(access.can_read) as can_read
  from
    "#{@pointer_table}" pointer
    join "#{@controlled_table}" controlled on true
    join "#{@grant_table}" g on controlled.acl_id = g.acl_id
    join "#{@access_table}" access on g.access_id = access.id
    left join "#{@circle_table}" circle on (g.subject_id = circle.id)
    left join "#{@encircle_table}" encircle
      on (circle.id = encircle.circle_id and encircle.subject_id = pointer.id)
  where (circle.id = pointer.id or encircle.id is not null)
  group by (pointer.id, controlled.id, access.id)
  """

  @drop_boundaries_see_read_view """
  drop view if exists boundaries_see_read
  """

  def migrate_views do
    Ecto.Migration.execute(
      @create_boundaries_see_read_view,
      @drop_boundaries_see_read_view
    )
  end

  defp mb(:up) do
    quote do
      require Bonfire.Data.AccessControl.Access.Migration
      require Bonfire.Data.AccessControl.Acl.Migration
      require Bonfire.Data.AccessControl.Circle.Migration
      require Bonfire.Data.AccessControl.Controlled.Migration
      require Bonfire.Data.AccessControl.Encircle.Migration
      require Bonfire.Data.AccessControl.Grant.Migration
      require Bonfire.Data.AccessControl.InstanceAdmin.Migration
      require Bonfire.Data.AccessControl.Interact.Migration
      require Bonfire.Data.AccessControl.Verb.Migration


      Bonfire.Data.AccessControl.Access.Migration.migrate_access()
      Bonfire.Data.AccessControl.Acl.Migration.migrate_acl()
      Bonfire.Data.AccessControl.Circle.Migration.migrate_circle()
      Bonfire.Data.AccessControl.Controlled.Migration.migrate_controlled()
      Bonfire.Data.AccessControl.Encircle.Migration.migrate_encircle()
      Bonfire.Data.AccessControl.Grant.Migration.migrate_grant()
      Bonfire.Data.AccessControl.InstanceAdmin.Migration.migrate_instance_admin()
      Bonfire.Data.AccessControl.Verb.Migration.migrate_verb()
      Bonfire.Data.AccessControl.Interact.Migration.migrate_interact()

      Ecto.Migration.flush()

      Bonfire.Boundaries.Migrations.migrate_functions()
      Bonfire.Boundaries.Migrations.migrate_views()

      # Ecto.Migration.flush()

      # insert initial data (moved to its own repo/migrations file)
      # Bonfire.Boundaries.Fixtures.insert()
    end
  end

  defp mb(:down) do
    quote do
      require Bonfire.Data.AccessControl.Access.Migration
      require Bonfire.Data.AccessControl.Acl.Migration
      require Bonfire.Data.AccessControl.Circle.Migration
      require Bonfire.Data.AccessControl.Controlled.Migration
      require Bonfire.Data.AccessControl.Encircle.Migration
      require Bonfire.Data.AccessControl.Grant.Migration
      require Bonfire.Data.AccessControl.InstanceAdmin.Migration
      require Bonfire.Data.AccessControl.Verb.Migration
      require Bonfire.Data.AccessControl.Interact.Migration

      Bonfire.Boundaries.Migrations.migrate_views()
      Bonfire.Boundaries.Migrations.migrate_functions()

      Bonfire.Data.AccessControl.Interact.Migration.migrate_interact()
      Bonfire.Data.AccessControl.Verb.Migration.migrate_verb()
      Bonfire.Data.AccessControl.InstanceAdmin.Migration.migrate_instance_admin()
      Bonfire.Data.AccessControl.Grant.Migration.migrate_grant()
      Bonfire.Data.AccessControl.Encircle.Migration.migrate_encircle()
      Bonfire.Data.AccessControl.Controlled.Migration.migrate_controlled()
      Bonfire.Data.AccessControl.Circle.Migration.migrate_circle()
      Bonfire.Data.AccessControl.Acl.Migration.migrate_acl()
      Bonfire.Data.AccessControl.Access.Migration.migrate_access()
    end
  end


  defmacro migrate_boundaries() do
    quote do
      if Ecto.Migration.direction() == :up,
        do: unquote(mb(:up)),
        else: unquote(mb(:down))
    end
  end
  defmacro migrate_boundaries(dir), do: mb(dir)

end
