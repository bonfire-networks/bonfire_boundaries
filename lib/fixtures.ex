defmodule Bonfire.Boundaries.Fixtures do

  alias Bonfire.Data.AccessControl.{Acl, Circle, Controlled, Grant, Verb}
  alias Bonfire.Data.Identity.Named
  alias Bonfire.Boundaries.{Verbs, Acls, Grants}
  alias Bonfire.Boundaries.Circles
  alias Pointers.ULID
  import Bonfire.Boundaries
  require Logger

  def insert() do
    acls = Map.values(Acls.acls()) # e.g. public, read_only
    circles = Map.values(Circles.circles()) # eg, guest, local, activity_pub
    verbs  = Map.values(Verbs.verbs()) # eg, read, see, create...
    grants =
      for {acl, entries}  <- Bonfire.Common.Config.get([:grants]),
          {circle, verbs} <- entries,
          verb            <- verbs do
        %{id:         ULID.generate(),
          acl_id:     Acls.get_id!(acl),
          subject_id: Circles.get_id!(circle),
          verb_id:    Verbs.get_id!(verb),
          value:      true}
      end
    Logger.error(":grants")
    named = Enum.filter(acls ++ circles, &(&1[:name]))
    Logger.error(":named")
    repo().insert_all(Acl,    Enum.map(acls,    &Map.take(&1, [:id])))
    repo().insert_all(Circle, Enum.map(circles, &Map.take(&1, [:id])))
    repo().insert_all(Verb,   verbs)
    repo().insert_all(Grant,  grants)
    # Then the mixins
    repo().insert_all(Named,  named)
  end

end
