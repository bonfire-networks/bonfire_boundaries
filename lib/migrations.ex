defmodule Bonfire.Boundaries.Migrations do
  @moduledoc false
  # alias Bonfire.Boundaries.Verbs

  # alias Needle.Pointer

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

      Bonfire.Boundaries.Summary.migrate(:up)
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

      Bonfire.Boundaries.Summary.migrate(:down)

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
  #     |> Needle.UID.cast!()
  #     |> Needle.ULID.dump()
  #   Needle.UUID.cast!(id)
  # end
end
