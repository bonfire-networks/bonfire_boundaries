defmodule Bonfire.Boundaries.Scaffold.Instance do
  @moduledoc """
  Provides functions to create default boundary fixtures for the instance.
  """
  import Bonfire.Boundaries.Integration
  import Untangle
  use Bonfire.Common.Utils
  alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.AccessControl.Circle
  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.AccessControl.Verb

  alias Bonfire.Data.Identity.Caretaker
  alias Bonfire.Data.Identity.Named

  alias Bonfire.Boundaries.Verbs
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Grants

  alias Bonfire.Boundaries.Circles
  alias Needle.ULID

  def custom_acl, do: "7HECVST0MAC1F0RAN0BJECTETC"
  def instance_acl, do: "01SETT1NGSF0R10CA11NSTANCE"
  def admin_circle, do: "0ADM1NSVSERW1THSVPERP0WERS"
  def mod_circle, do: "10VE1YM0DSHE1PHEA1THYC0MMS"
  def activity_pub_circle, do: "7EDERATEDW1THANACT1V1TYPVB"
  def suggested_profiles_circle, do: "5VGGESTEDPR0F11EST0F0110WS"

  # TODO: generate from config

  def public_global_circles,
    do: [
      "3SERSFR0MY0VR10CA11NSTANCE",
      activity_pub_circle(),
      admin_circle(),
      mod_circle(),
      suggested_profiles_circle()
    ]

  def global_circles,
    do:
      public_global_circles() ++
        [
          "0AND0MSTRANGERS0FF1NTERNET"
        ]

  defp list_verbs(verbs) when is_list(verbs) or is_map(verbs), do: verbs

  defp list_verbs(role) when is_atom(role) do
    role = Boundaries.Roles.get(role)

    (role
     |> e(:can_verbs, [])
     |> Enum.map(&{&1, true})) ++
      (role
       |> e(:cannot_verbs, [])
       |> Enum.map(&{&1, false}))
  end

  defp upsert_verbs_helper(verbs) do
    repo().insert_all_or_ignore(Verb, Enum.map(verbs, &Map.take(&1, [:id, :verb])))
    |> info("Init verbs")
  end

  defp upsert_circles_helper(circles) do
    repo().insert_all_or_ignore(Circle, Enum.map(circles, &Map.take(&1, [:id])))
    |> info("Init circles")

    # Ensure each public_global_circle is linked to the public ACL
    public_acl_id = Bonfire.Boundaries.Acls.get_id!(:everyone_may_see_read)

    repo().insert_all_or_ignore(
      Bonfire.Data.AccessControl.Controlled,
      Enum.map(public_global_circles(), fn circle_id ->
        %{id: circle_id, acl_id: public_acl_id}
      end)
    )
    |> info("Linked public_global_circles to public ACL")

    mods_manage_acl_id = Bonfire.Boundaries.Acls.get_id!(:mods_may_manage)

    repo().insert_all_or_ignore(
      Bonfire.Data.AccessControl.Controlled,
      [%{id: suggested_profiles_circle(), acl_id: mods_manage_acl_id}]
    )
    |> info("Linked suggested_profiles_circle to mods_may_manage ACL")
  end

  defp upsert_acls_helper(acls) do
    repo().insert_all_or_ignore(Acl, Enum.map(acls, &Map.take(&1, [:id])))
    |> info("Init ACLs")
  end

  defp upsert_grants_helper(grants) do
    # then grants
    # First deduplicate grants by [:acl_id, :subject_id, :verb_id]
    deduped_grants =
      Grants.uniq_grants_to_create(grants)
      |> debug("deduped grants")

    repo().upsert_all(Grant, deduped_grants, [:acl_id, :subject_id, :verb_id])
    |> debug("Init or update grants")
  end

  defp grants_fixtures do
    for {acl, entries} <- Grants.grants(),
        {circle, role_or_verbs} <- entries,
        verb <- list_verbs(role_or_verbs) |> debug("list_verbs") do
      debug(verb)

      %{
        id: Needle.UID.generate(),
        acl_id: Acls.get_id!(acl),
        subject_id: Circles.get_id!(circle),
        verb_id: Verbs.get_id!(Enums.maybe_elem(verb, 0) || verb),
        # if no monoid specified in config, default to positive grant
        value: Enums.maybe_elem(verb, 1, true)
      }
    end
    |> debug("grants")
  end

  @doc """
  Prepares and returns the fixtures for ACLs, circles, verbs, named entities, and grants.
  """
  def fixtures() do
    # e.g. public, read_only
    acls = Map.values(Acls.acls())
    # |> debug("ACLs")

    # eg, guest, local, activity_pub
    circles = Map.values(Circles.circles())

    # eg, read, see, create...
    verbs = Keyword.values(Verbs.verbs())

    named = Enum.filter(acls ++ circles, & &1[:name])

    grants = grants_fixtures()

    %{
      acls: acls,
      circles: circles,
      verbs: verbs,
      named: named,
      grants: grants
    }
  end

  @doc """
  Prepares fixtures and inserts them into the database.
  """
  def insert() do
    %{acls: acls, circles: circles, verbs: verbs, named: named, grants: grants} = fixtures()

    upsert_acls_helper(acls)

    upsert_circles_helper(circles)

    upsert_verbs_helper(verbs)

    upsert_grants_helper(grants)

    # Then the mixins
    repo().insert_all_or_ignore(Named, Enum.map(named, &Map.take(&1, [:id, :name])))
    |> info("Add names")

    # Make the instance admins circle caretaker of global circles and ACLs
    repo().insert_all_or_ignore(
      Caretaker,
      uids(acls ++ circles)
      |> Enum.map(&%{id: &1, caretaker_id: admin_circle()})
    )
    |> info("Init caretakers")

    # make the instance ACL control the instance object (which are the same)
    Bonfire.Boundaries.Controlleds.add_acls(instance_acl(), instance_acl())
    |> info("Init instance ACL")

    :ok
  end

  @doc """
  Inserts or updates the verbs in the database.
  """
  def upsert_verbs() do
    upsert_verbs_helper(Keyword.values(Verbs.verbs()))
    :ok
  end

  @doc """
  Inserts or updates circles in the database.

  Useful for migrations when adding new built-in circles. This will:
  - Insert the circle records (ignoring if they already exist)
  - Add names for the circles
  - Set up caretakers (admin circle as caretaker)
  """
  def upsert_circles() do
    circles = Map.values(Circles.circles())

    upsert_circles_helper(circles)

    named = Enum.filter(circles, & &1[:name])

    repo().insert_all_or_ignore(Named, Enum.map(named, &Map.take(&1, [:id, :name])))
    |> info("Add circle names")

    repo().insert_all_or_ignore(
      Caretaker,
      uids(circles) |> Enum.map(&%{id: &1, caretaker_id: admin_circle()})
    )
    |> info("Init circle caretakers")

    :ok
  end

  @doc """
  Inserts or updates the ACLs in the database.

  Useful for migrations when adding new built-in ACLs. This will:
  - Insert the ACL records (ignoring if they already exist)
  """
  def upsert_acls() do
    Map.values(Acls.acls())
    |> upsert_acls_helper()

    grants_fixtures()
    |> upsert_grants_helper()

    :ok
  end
end
