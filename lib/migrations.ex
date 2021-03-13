defmodule Bonfire.Boundaries.Migrations do

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
    # this has the appearance of being muddled, but it's not
    Ecto.Migration.execute(@create_add_perms, @drop_agg_perms)
    Ecto.Migration.execute(@create_agg_perms, @drop_add_perms)
  end

  defp mb(:up) do
    quote do
      require Bonfire.Data.AccessControl.Access.Migration
      require Bonfire.Data.AccessControl.Acl.Migration
      require Bonfire.Data.AccessControl.Controlled.Migration
      require Bonfire.Data.AccessControl.Grant.Migration
      require Bonfire.Data.AccessControl.InstanceAdmin.Migration
      require Bonfire.Data.AccessControl.Interact.Migration
      require Bonfire.Data.AccessControl.Verb.Migration


      Bonfire.Data.AccessControl.Access.Migration.migrate_access()
      Bonfire.Data.AccessControl.Acl.Migration.migrate_acl()
      Bonfire.Data.AccessControl.Controlled.Migration.migrate_controlled()
      Bonfire.Data.AccessControl.Grant.Migration.migrate_grant()
      Bonfire.Data.AccessControl.InstanceAdmin.Migration.migrate_instance_admin()
      Bonfire.Data.AccessControl.Verb.Migration.migrate_verb()
      Bonfire.Data.AccessControl.Interact.Migration.migrate_interact()

      Bonfire.Boundaries.Migrations.migrate_functions()

      Ecto.Migration.flush()

      # insert initial data
      Bonfire.Boundaries.Fixtures.insert()
    end
  end

  defp mb(:down) do
    quote do
      require Bonfire.Data.AccessControl.Access.Migration
      require Bonfire.Data.AccessControl.Acl.Migration
      require Bonfire.Data.AccessControl.Controlled.Migration
      require Bonfire.Data.AccessControl.Grant.Migration
      require Bonfire.Data.AccessControl.InstanceAdmin.Migration
      require Bonfire.Data.AccessControl.Verb.Migration
      require Bonfire.Data.AccessControl.Interact.Migration

      Bonfire.Boundaries.Migrations.migrate_functions()

      Bonfire.Data.AccessControl.Interact.Migration.migrate_interact()
      Bonfire.Data.AccessControl.Verb.Migration.migrate_verb()
      Bonfire.Data.AccessControl.InstanceAdmin.Migration.migrate_instance_admin()
      Bonfire.Data.AccessControl.Grant.Migration.migrate_grant()
      Bonfire.Data.AccessControl.Controlled.Migration.migrate_controlled()
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
