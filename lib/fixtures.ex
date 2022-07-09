defmodule Bonfire.Boundaries.Fixtures do

  import Bonfire.Boundaries.Integration
  # import Where
  alias Bonfire.Common.Utils
  alias Bonfire.Data.AccessControl.{Acl, Circle, Grant, Verb}
  alias Bonfire.Data.Identity.Named
  alias Bonfire.Boundaries.{Verbs, Acls, Grants}
  alias Bonfire.Boundaries.Circles
  alias Pointers.ULID

  def insert() do
    acls = Map.values(Acls.acls()) # e.g. public, read_only
    circles = Map.values(Circles.circles()) # eg, guest, local, activity_pub
    verbs  = Map.values(Verbs.verbs()) # eg, read, see, create...
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
    named = Enum.filter(acls ++ circles, &(&1[:name]))
    repo().insert_all_or_ignore(Acl,    Enum.map(acls,    &Map.take(&1, [:id])))
    repo().insert_all_or_ignore(Circle, Enum.map(circles, &Map.take(&1, [:id])))
    repo().insert_all_or_ignore(Verb,   Enum.map(verbs,   &Map.take(&1, [:id, :verb])))
    repo().insert_all_or_ignore(Grant,  grants)
    # Then the mixins
    repo().insert_all_or_ignore(Named,  named)
  end

end
