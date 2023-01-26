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

  def instance_acl, do: "01SETT1NGSF0R10CA11NSTANCE"
  def admin_circle, do: "0ADM1NSVSERW1THSVPERP0WERS"
  # TODO: generate from config
  def global_circles,
    do: [
      "0AND0MSTRANGERS0FF1NTERNET",
      "3SERSFR0MY0VR10CA11NSTANCE",
      "7EDERATEDW1THANACT1V1TYPVB",
      admin_circle
    ]

  def insert() do
    # e.g. public, read_only
    acls = Map.values(Acls.acls())
    # eg, guest, local, activity_pub
    circles = Map.values(Circles.circles())
    # eg, read, see, create...
    verbs = Keyword.values(Verbs.verbs())
    named = Enum.filter(acls ++ circles, & &1[:name])

    grants =
      for {acl, entries} <- Grants.grants(),
          {circle, verbs} <- entries,
          verb <- verbs do
        %{
          id: ULID.generate(),
          acl_id: Acls.get_id!(acl),
          subject_id: Circles.get_id!(circle),
          verb_id: Verbs.get_id!(Enums.elem_or(verb, 0, verb)),
          # if no monoid specified in config, default to positive grant
          value: Enums.elem_or(verb, 1, true)
        }
      end

    repo().insert_all_or_ignore(Acl, Enum.map(acls, &Map.take(&1, [:id])))
    repo().insert_all_or_ignore(Circle, Enum.map(circles, &Map.take(&1, [:id])))

    repo().insert_all_or_ignore(
      Verb,
      Enum.map(verbs, &Map.take(&1, [:id, :verb]))
    )

    # then grants
    repo().insert_all_or_ignore(Grant, grants) |> debug("grants added")

    # Then the mixins
    repo().insert_all_or_ignore(
      Named,
      Enum.map(named, &Map.take(&1, [:id, :name]))
    )

    # Make the instance admins circle caretaker of global circles and ACLs
    repo().insert_all_or_ignore(
      Caretaker,
      ulids(acls ++ circles)
      |> Enum.map(&%{id: &1, caretaker_id: admin_circle})
    )
    |> info("Init built-in verbs and boundaries")

    # make the instance ACL control the instance object (which are the same)
    Bonfire.Boundaries.Controlleds.add_acls(instance_acl, instance_acl)
  end
end
