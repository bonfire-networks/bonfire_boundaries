defmodule Bonfire.Boundaries.Fixtures do

  alias Bonfire.Data.AccessControl.{Access, Acl, Controlled, Grant, Interact, Verb}
  alias Bonfire.Data.Identity.Named
  alias Bonfire.Data.Social.Circle
  alias Bonfire.Boundaries.{Accesses, Verbs, Acls, Grants}
  alias Bonfire.Boundaries.Circles
  # alias Ecto.UUID
  alias Pointers.ULID
  import Bonfire.Boundaries

  def insert() do

    # to start with, we need our special circles (eg, guest, local, activity_pub, admin)
    circles = Circles.circles()

    repo().insert_all(
      Circle,
      Circles.circles_fixture(),
      on_conflict: :nothing
    )

    # give the circles some names
    repo().insert_all(
      Named,
      Circles.circles_named_fixture(),
      on_conflict: :nothing
    )

    # now we need to insert verbs for our standard actions (eg, read, see, create...)
    verbs  = Verbs.verbs()

    repo().insert_all(
      Verb,
      Verbs.verbs_fixture(),
      on_conflict: :nothing
    )

    # then our standard accesses (eg, read_only, administer)
    accesses = Accesses.accesses()

    repo().insert_all(
      Access,
      Accesses.accesses_fixture(),
      on_conflict: :nothing
    )

    # now we have to hook up the permission-related verbs to the accesses
    repo().insert_all(
      Interact,
      [
        %{id: ULID.generate(), access_id: accesses.read_only,  verb_id: verbs.read},
        %{id: ULID.generate(), access_id: accesses.read_only,  verb_id: verbs.see},
        %{id: ULID.generate(), access_id: accesses.administer, verb_id: verbs.read},
        %{id: ULID.generate(), access_id: accesses.administer, verb_id: verbs.see},
        %{id: ULID.generate(), access_id: accesses.administer, verb_id: verbs.edit},
        %{id: ULID.generate(), access_id: accesses.administer, verb_id: verbs.delete},
      ],
      on_conflict: :nothing
    )

    # say no (false) for every verb in the no_no_no access
    repo().insert_all(
      Interact,
      Enum.map(verbs, fn {_, v} -> %{id: ULID.generate(), access_id: accesses.no_no_no, verb_id: v, value: false} end),
      on_conflict: :nothing
    )

    # some of these things are public
    # the read_only ACL and the read Verb are visible to local users, so they need an
    # acl and a controlled mixin that associates them
    acls = Acls.acls()

    repo().insert_all(
      Acl,
      Acls.acls_fixture(),
      on_conflict: :nothing
    )

    repo().insert_all(
      Controlled,
      [
        %{id: verbs.read,     acl_id: acls.read_only},
        %{id: acls.read_only, acl_id: acls.read_only},
      ],
      on_conflict: :nothing
    )

    # finally, we do a horrible thing and grant read_only to
    # read_only_acl and it actually kinda works out because of the
    # indirection through pointer
    # so it's recursive - we use the access control to access control the access control
    grants = Grants.grants()

    repo().insert_all(
      Grant,
      [
        %{
         id:         grants.read_only,
         acl_id:     acls.read_only, # what (list of) things we are granting access to
         access_id:  accesses.read_only, # what level of access
         subject_id: circles.local # who we are granting access to
        },
      ],
      on_conflict: :nothing
    )
  end

end
