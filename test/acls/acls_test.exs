defmodule Bonfire.Boundaries.AclTest do
  use Bonfire.Boundaries.DataCase, async: true
  alias Bonfire.Data.AccessControl.Circle
  alias Bonfire.Me.Fake
  alias Bonfire.Me.Users
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Grants

  # test "listing instance-wide acls (which I am permitted to see) works" do
  #   user = fake_user!()

  #   assert acls = Acls.list_visible(user)
  #   #preset_acls = Bonfire.Boundaries.Circles.circles() |> Map.keys()
  #   assert length(acls) == 0 #length(preset_acls)
  # end

  test "creation works" do
    user = fake_user!()
    name = "test acl"

    assert {:ok, acl} =
             Acls.simple_create(user, name)
             |> repo().maybe_preload([:named, :caretaker])

    assert name == acl.named.name
    assert user.id == acl.caretaker.caretaker_id
  end

  test "listing my ACLs (which I'm caretaker of) works" do
    user = fake_user!()
    name = "test circle"
    assert {:ok, acl} = Acls.simple_create(user, name)

    assert acls =
             Acls.list_my(user)
             |> debug("myacls")

    # is this right?
    assert is_list(acls) and length(acls) > 3

    my_acl = List.last(acls)
    my_acl = repo().maybe_preload(my_acl, [:named, :caretaker])

    assert name == my_acl.named.name
    assert user.id == my_acl.caretaker.caretaker_id
  end

  test "cannot list someone else's ACLs (which they're caretaker of) " do
    user = fake_user!()
    name = "test circle"
    assert {:ok, circle} = Acls.simple_create(user, name)

    me = fake_user!()

    assert acls =
             Acls.list_my(me)
             |> debug("myacls")

    # is this right?
    assert length(acls) == 3
  end

  # test "cannot list ACLs which I am not permitted to see" do
  #   me = fake_user!()
  #   user = fake_user!()
  #   name = "test circle by other user"
  #   assert {:ok, acl} = Acls.simple_create(user, name)

  #   assert acls = Acls.list_visible(me)
  #   |> Repo.preload([:named, :caretaker])

  #   #debug(acls)
  #   assert length(acls) == 0
  # end

  test "can create a ACL, add circles and people to it, and grant them some verbs" do
    name = "family trip"
    # create a bunch of users
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)
    carl = fake_user!(account)

    {:ok, acl} = Acls.simple_create(me, name)

    # create a circle with alice and bob
    {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
    {:ok, _} = Circles.add_to_circles(alice, circle)

    assert Bonfire.Boundaries.Circles.is_encircled_by?(alice, circle)

    # add circles/users to Acl
    Grants.grant(circle.id, acl.id, :edit, true, current_user: me)
    Grants.grant(bob.id, acl.id, :edit, true, current_user: me)

    {:ok, acl} =
      Acls.get_for_caretaker(acl.id, me)
      |> repo().maybe_preload(
        grants: [
          :verb,
          subject: [:named, :profile, :character, stereotyped: [:named]]
        ]
      )

    # check that the circle and alice are now in the ACL and that alice and bob have edit permission
    assert Enum.count(acl.grants, fn grant ->
             grant.subject_id in [circle.id, bob.id] and grant.verb.verb == "Edit"
           end) == 2

    # check that carl doesn't
    refute Enum.any?(acl.grants, fn grant -> grant.subject_id in [carl.id] end)
  end

  test "can create a ACL, add circles and people to it, and grant them some roles" do
    name = "family trip"
    # create a bunch of users
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)
    bob = fake_user!(account)
    carl = fake_user!(account)

    {:ok, acl} = Acls.simple_create(me, name)

    # create a circle with alice and bob
    {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
    {:ok, _} = Circles.add_to_circles(alice, circle)

    assert Bonfire.Boundaries.Circles.is_encircled_by?(alice, circle)

    # add circles/users to Acl
    Grants.grant_role(circle.id, acl.id, "contribute", current_user: me)
    Grants.grant_role(bob.id, acl.id, "contribute", current_user: me)

    {:ok, acl} =
      Acls.get_for_caretaker(acl.id, me)
      |> repo().maybe_preload(
        grants: [
          :verb,
          subject: [:named, :profile, :character, stereotyped: [:named]]
        ]
      )

    # check that the circle and alice are now in the ACL and that alice and bob have create permission
    assert Enum.count(acl.grants, fn grant ->
             grant.subject_id in [circle.id, bob.id] and grant.verb.verb == "Create"
           end) == 2

    # TODO check that alice and bob have permission for ALL the "contribute" verbs?

    # check that carl doesn't
    refute Enum.any?(acl.grants, fn grant -> grant.subject_id in [carl.id] end)
  end

  test "can correctly edit the role of someone on a ACL" do
    name = "family trip"
    # create a bunch of users
    account = fake_account!()
    me = fake_user!(account)
    bob = fake_user!(account)

    {:ok, acl} = Acls.simple_create(me, name)

    # add bob to Acl
    Grants.grant_role(bob.id, acl.id, "read", current_user: me)

    # upgrade bob's role
    Grants.grant_role(bob.id, acl.id, "contribute", current_user: me)

    {:ok, acl} =
      Acls.get_for_caretaker(acl.id, me)
      |> repo().maybe_preload(
        grants: [
          :verb,
          subject: [:named, :profile, :character, stereotyped: [:named]]
        ]
      )

    # check bob has create permission
    assert Enum.any?(acl.grants, fn grant ->
             grant.subject_id == bob.id and grant.verb.verb == "Create"
           end)

    # downgrade bob's role
    Grants.grant_role(bob.id, acl.id, "read", current_user: me)

    {:ok, acl} =
      Acls.get_for_caretaker(acl.id, me)
      |> repo().maybe_preload(
        grants: [
          :verb,
          subject: [:named, :profile, :character, stereotyped: [:named]]
        ]
      )

    # check that bob no longer has create permission
    refute Enum.any?(acl.grants, fn grant ->
             grant.subject_id == bob.id and grant.verb.verb == "Create"
           end)

    # but he can still read
    assert Enum.any?(acl.grants, fn grant ->
             grant.subject_id == bob.id and grant.verb.verb == "Read"
           end)
  end
end
