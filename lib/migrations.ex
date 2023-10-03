defmodule Bonfire.Boundaries.Migrations do
  @moduledoc false
  # alias Bonfire.Boundaries.Verbs

  # alias Pointers.Pointer

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

  defp mb(:up) do
    quote do
      require Bonfire.Data.AccessControl.Acl.Migration
      require Bonfire.Data.AccessControl.Circle.Migration
      require Bonfire.Data.AccessControl.Controlled.Migration
      require Bonfire.Data.AccessControl.Encircle.Migration
      require Bonfire.Data.AccessControl.Grant.Migration
      require Bonfire.Data.AccessControl.InstanceAdmin.Migration
      require Bonfire.Data.AccessControl.Verb.Migration
      require Bonfire.Data.AccessControl.Stereotyped.Migration

      Bonfire.Data.AccessControl.Acl.Migration.migrate_acl()
      Bonfire.Data.AccessControl.Circle.Migration.migrate_circle()
      Bonfire.Data.AccessControl.Controlled.Migration.migrate_controlled()
      Bonfire.Data.AccessControl.Encircle.Migration.migrate_encircle()
      Bonfire.Data.AccessControl.Verb.Migration.migrate_verb()
      Bonfire.Data.AccessControl.Grant.Migration.migrate_grant()

      Bonfire.Data.AccessControl.InstanceAdmin.Migration.migrate_instance_admin()

      Bonfire.Data.AccessControl.Stereotyped.Migration.migrate_stereotype()

      Ecto.Migration.flush()

      Bonfire.Boundaries.Migrations.migrate_functions()
      Bonfire.Boundaries.Summary.migrate_views()
    end
  end

  defp mb(:down) do
    quote do
      require Bonfire.Data.AccessControl.Acl.Migration
      require Bonfire.Data.AccessControl.Circle.Migration
      require Bonfire.Data.AccessControl.Controlled.Migration
      require Bonfire.Data.AccessControl.Encircle.Migration
      require Bonfire.Data.AccessControl.Grant.Migration
      require Bonfire.Data.AccessControl.InstanceAdmin.Migration
      require Bonfire.Data.AccessControl.Verb.Migration
      require Bonfire.Data.AccessControl.Stereotyped.Migration

      Bonfire.Boundaries.Summary.migrate_views()
      Bonfire.Boundaries.Migrations.migrate_functions()

      Bonfire.Data.AccessControl.Stereotyped.Migration.migrate_stereotype()

      Bonfire.Data.AccessControl.InstanceAdmin.Migration.migrate_instance_admin()

      Bonfire.Data.AccessControl.Grant.Migration.migrate_grant()
      Bonfire.Data.AccessControl.Verb.Migration.migrate_verb()
      Bonfire.Data.AccessControl.Encircle.Migration.migrate_encircle()
      Bonfire.Data.AccessControl.Controlled.Migration.migrate_controlled()
      Bonfire.Data.AccessControl.Circle.Migration.migrate_circle()
      Bonfire.Data.AccessControl.Acl.Migration.migrate_acl()
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

  # retrieves a ULID in UUID format
  # defp verb!(id) do
  #   # the verbs service is unlikely to be running...
  #   {:ok, id} =
  #     Verbs.declare_verbs()[:verbs]
  #     |> Map.fetch!(id)
  #     |> Pointers.ULID.cast!()
  #     |> Pointers.ULID.dump()
  #   Pointers.UUID.cast!(id)
  # end
end
