defmodule Bonfire.Boundaries.Fixtures do

  import Bonfire.Boundaries.Integration
  import Where
  alias Bonfire.Common.Utils
  alias Bonfire.Data.AccessControl.{Acl, Circle, Grant, Verb}
  alias Bonfire.Data.Identity.{Caretaker, Named}
  alias Bonfire.Boundaries.{Verbs, Acls, Grants}
  alias Bonfire.Boundaries.Circles
  alias Pointers.ULID


  def instance_acl, do: "01SETT1NGSF0R10CA11NSTANCE"
  def admin_circle, do: "0ADM1NSVSERW1THSVPERP0WERS"
  def global_circles, do: ["0AND0MSTRANGERS0FF1NTERNET", "3SERSFR0MY0VR10CA11NSTANCE", "7EDERATEDW1THANACT1V1TYPVB", admin_circle] # TODO: generate from config


  def insert() do

    acls = Map.values(Acls.acls()) # e.g. public, read_only
    circles = Map.values(Circles.circles()) # eg, guest, local, activity_pub
    verbs  = Map.values(Verbs.verbs()) # eg, read, see, create...
    named = Enum.filter(acls ++ circles, &(&1[:name]))

    grants =
      for {acl, entries}  <- Grants.grants(),
          {circle, verbs} <- entries,
          verb            <- verbs do
        %{id:         ULID.generate(),
          acl_id:     Acls.get_id!(acl),
          subject_id: Circles.get_id!(circle),
          verb_id:    Verbs.get_id!(Utils.elem_or(verb, 0, verb)),
          value:      Utils.elem_or(verb, 1, true)} # if no monoid specified in config, default to positive grant
      end

    repo().insert_all_or_ignore(Acl,    Enum.map(acls,    &Map.take(&1, [:id])))
    repo().insert_all_or_ignore(Circle, Enum.map(circles, &Map.take(&1, [:id])))
    repo().insert_all_or_ignore(Verb,   Enum.map(verbs,   &Map.take(&1, [:id, :verb])))

    # then grants
    repo().insert_all_or_ignore(Grant,  grants) |> debug("grants added")

    # Then the mixins
    repo().insert_all_or_ignore(Named,  Enum.map(named,   &Map.take(&1, [:id, :name])))

    # Make the instance admins circle caretaker of global circles and ACLs
    repo().insert_all_or_ignore(Caretaker, Utils.ulids(acls ++ circles) |> Enum.map(& %{id: &1, caretaker_id: admin_circle }))

    # make the instance ACL control the instance object (which are the same)
    Bonfire.Boundaries.Controlleds.add_acls(instance_acl, instance_acl)
  end

end
