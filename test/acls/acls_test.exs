defmodule Bonfire.Boundaries.AclTest do
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Data.AccessControl.Circle
  alias Bonfire.Me.Fake
  alias Bonfire.Me.Users
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Grants

  # test "listing instance-wide acls (which I am permitted to see) works" do
  #   user = Bonfire.Me.Fake.fake_user!()

  #   assert acls = Acls.list_visible(user)
  #   #preset_acls = Bonfire.Boundaries.Circles.circles() |> Map.keys()
  #   assert length(acls) == 0 #length(preset_acls)
  # end

  test "creation works" do
    user = Bonfire.Me.Fake.fake_user!()
    name = "test acl"

    assert {:ok, acl} =
             Acls.simple_create(user, name)
             |> repo().maybe_preload([:named, :caretaker])

    assert name == acl.named.name
    assert user.id == acl.caretaker.caretaker_id
  end

  test "listing my ACLs (which I'm caretaker of) works" do
    user = Bonfire.Me.Fake.fake_user!()
    name = "test circle"
    assert {:ok, acl} = Acls.simple_create(user, name)

    assert acls =
             Acls.list_my(user)
             |> debug("myacls")

    acls = e(acls, :edges, nil) || acls

    # is this right?
    # assert is_list(acls) and length(acls) > 3
    assert is_list(acls) and length(acls) > 0

    my_acl = Enum.find(acls, fn %{id: id} -> id == acl.id end)
    my_acl = repo().maybe_preload(my_acl, [:named, :caretaker])

    assert name == e(my_acl, :named, :name, nil)
    assert user.id == e(my_acl, :caretaker, :caretaker_id, nil)
  end

  test "cannot list someone else's ACLs (which they're caretaker of) " do
    user = Bonfire.Me.Fake.fake_user!()
    name = "test circle"
    assert {:ok, circle} = Acls.simple_create(user, name)

    me = Bonfire.Me.Fake.fake_user!()

    assert acls =
             Acls.list_my(me)
             |> debug("myacls")

    # is this right?
    assert length(acls.edges) <= 4
  end

  # test "cannot list ACLs which I am not permitted to see" do
  #   me = Bonfire.Me.Fake.fake_user!()
  #   user = Bonfire.Me.Fake.fake_user!()
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
    account = Bonfire.Me.Fake.fake_account!()
    me = Bonfire.Me.Fake.fake_user!(account)
    alice = Bonfire.Me.Fake.fake_user!(account)
    bob = Bonfire.Me.Fake.fake_user!(account)
    carl = Bonfire.Me.Fake.fake_user!(account)

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
    account = Bonfire.Me.Fake.fake_account!()
    me = Bonfire.Me.Fake.fake_user!(account)
    alice = Bonfire.Me.Fake.fake_user!(account)
    bob = Bonfire.Me.Fake.fake_user!(account)
    carl = Bonfire.Me.Fake.fake_user!(account)

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
    account = Bonfire.Me.Fake.fake_account!()
    me = Bonfire.Me.Fake.fake_user!(account)
    bob = Bonfire.Me.Fake.fake_user!(account)

    {:ok, acl} = Acls.simple_create(me, name)

    # add bob to Acl
    Grants.grant_role(bob.id, acl.id, "cannot_participate", current_user: me)
    |> debug("1stgrant")

    {:ok, acl} =
      Acls.get_for_caretaker(acl.id, me)
      |> repo().maybe_preload(
        grants: [
          :verb,
          subject: [:named, :profile, :character, stereotyped: [:named]]
        ]
      )

    # check bob is not blocked from reading
    refute Enum.any?(acl.grants, fn grant ->
             grant.subject_id == bob.id and grant.verb.verb == "Read" and grant.value == false
           end)

    # check bob has no reply permission
    assert Enum.any?(acl.grants, fn grant ->
             grant.subject_id == bob.id and grant.verb.verb == "Reply" and grant.value == false
           end)

    # change bob's role
    Grants.change_role(bob.id, acl.id, "cannot_read", current_user: me)
    |> debug("2ndgrant")

    {:ok, acl} =
      Acls.get_for_caretaker(acl.id, me)
      |> repo().maybe_preload(
        grants: [
          :verb,
          subject: [:named, :profile, :character, stereotyped: [:named]]
        ]
      )

    # check bob has no read permission
    assert Enum.any?(acl.grants, fn grant ->
             grant.subject_id == bob.id and grant.verb.verb == "Read" and grant.value == false
           end)

    # check bob still has no reply permission either
    assert Enum.any?(acl.grants, fn grant ->
             grant.subject_id == bob.id and grant.verb.verb == "Reply" and grant.value == false
           end)

    # change bob's role
    Grants.change_role(bob.id, acl.id, "cannot_participate", current_user: me)
    |> debug("3rdgrant")

    {:ok, acl} =
      Acls.get_for_caretaker(acl.id, me)
      |> repo().maybe_preload(
        grants: [
          :verb,
          subject: [:named, :profile, :character, stereotyped: [:named]]
        ]
      )

    # check that bob still has no reply permission again
    assert Enum.any?(acl.grants, fn grant ->
             grant.subject_id == bob.id and grant.verb.verb == "Reply" and grant.value == false
           end)

    # but he can can read again
    refute Enum.any?(acl.grants, fn grant ->
             grant.subject_id == bob.id and grant.verb.verb == "Read" and grant.value == false
           end)
  end
end
