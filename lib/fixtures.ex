defmodule Bonfire.Boundaries.Fixtures do
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
  alias Pointers.ULID

  def custom_acl, do: "7HECVST0MAC1F0RAN0BJECTETC"
  def instance_acl, do: "01SETT1NGSF0R10CA11NSTANCE"
  def admin_circle, do: "0ADM1NSVSERW1THSVPERP0WERS"
  def mod_circle, do: "10VE1YM0DSHE1PHEA1THYC0MMS"
  def activity_pub_circle, do: "7EDERATEDW1THANACT1V1TYPVB"

  # TODO: generate from config
  def global_circles,
    do: [
      "0AND0MSTRANGERS0FF1NTERNET",
      "3SERSFR0MY0VR10CA11NSTANCE",
      activity_pub_circle(),
      admin_circle()
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

  def fixtures() do
    # e.g. public, read_only
    acls = Map.values(Acls.acls())
    # |> debug("ACLs")

    # eg, guest, local, activity_pub
    circles = Map.values(Circles.circles())

    # eg, read, see, create...
    verbs = Keyword.values(Verbs.verbs())

    named = Enum.filter(acls ++ circles, & &1[:name])

    grants =
      for {acl, entries} <- Grants.grants(),
          {circle, role_or_verbs} <- entries,
          verb <- list_verbs(role_or_verbs) |> debug("list_verbs") do
        debug(verb)

        %{
          id: ULID.generate(),
          acl_id: Acls.get_id!(acl),
          subject_id: Circles.get_id!(circle),
          verb_id: Verbs.get_id!(Enums.maybe_elem(verb, 0) || verb),
          # if no monoid specified in config, default to positive grant
          value: Enums.maybe_elem(verb, 1, true)
        }
      end
      |> dump("grants")

    %{
      acls: acls,
      circles: circles,
      verbs: verbs,
      named: named,
      grants: grants
    }
  end

  def insert() do
    %{
      acls: acls,
      circles: circles,
      verbs: verbs,
      named: named,
      grants: grants
    } = fixtures()

    repo().insert_all_or_ignore(Acl, Enum.map(acls, &Map.take(&1, [:id])))
    |> info("Init ACLs")

    repo().insert_all_or_ignore(Circle, Enum.map(circles, &Map.take(&1, [:id])))
    |> info("Init circles")

    repo().insert_all_or_ignore(
      Verb,
      Enum.map(verbs, &Map.take(&1, [:id, :verb]))
    )
    |> info("Init verbs")

    # then grants
    repo().upsert_all(Grant, grants, [:acl_id, :subject_id, :verb_id])
    |> info("Init or update grants")

    # Then the mixins
    repo().insert_all_or_ignore(
      Named,
      Enum.map(named, &Map.take(&1, [:id, :name]))
    )
    |> info("Add names")

    # Make the instance admins circle caretaker of global circles and ACLs
    repo().insert_all_or_ignore(
      Caretaker,
      ulids(acls ++ circles)
      |> Enum.map(&%{id: &1, caretaker_id: admin_circle()})
    )
    |> info("Init caretakers")

    # make the instance ACL control the instance object (which are the same)
    Bonfire.Boundaries.Controlleds.add_acls(instance_acl(), instance_acl())
    |> info("Init instance ACL")

    :ok
  end
end
