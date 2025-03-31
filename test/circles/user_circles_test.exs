defmodule Bonfire.Boundaries.UserCirclesTest do
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Data.AccessControl.Circle
  alias Bonfire.Me.Fake
  alias Bonfire.Me.Users
  alias Bonfire.Boundaries.Circles

  test "listing instance-wide circles (which I am permitted to see) works" do
    user = Bonfire.Me.Fake.fake_user!()

    assert circles = Circles.list_visible(user)
    # preset_circles = Bonfire.Boundaries.Circles.circles() |> Map.keys()
    # length(preset_circles)
    assert length(circles) == 0
  end

  test "creation works" do
    user = Bonfire.Me.Fake.fake_user!()
    name = "test circle"
    assert {:ok, circle} = Circles.create(user, name)
    assert name == circle.named.name
    assert user.id == circle.caretaker.caretaker_id
  end

  test "listing my circles (which I'm caretaker of) works" do
    user = Bonfire.Me.Fake.fake_user!()
    name = "test circle"
    assert {:ok, circle} = Circles.create(user, name)

    assert circles =
             Circles.list_my(user)
             |> debug("mycircles")

    circles = e(circles, :edges, nil) || circles

    assert is_list(circles)
    # is this right?
    # assert length(circles) > length(Bonfire.Boundaries.Circles.list_built_ins()) - 5
    assert length(circles) > 0

    # my_circle = List.last(circles)
    my_circle = Enum.find(circles, fn %{id: id} -> id == circle.id end)
    my_circle = repo().maybe_preload(my_circle, [:named, :caretaker])

    assert name == my_circle.named.name
    assert user.id == my_circle.caretaker.caretaker_id
  end

  test "cannot list someone else's circles (which they're caretaker of) " do
    user = Bonfire.Me.Fake.fake_user!()
    name = "test circle"
    assert {:ok, circle} = Circles.create(user, name)

    me = Bonfire.Me.Fake.fake_user!()

    assert circles =
             Circles.list_my(me)
             |> debug("mycircles")

    # is this right?
    assert length(circles) <= length(Bonfire.Boundaries.Circles.list_built_ins()) - 5
  end

  # test "listing circles I am permitted to see works" do
  #   user = Bonfire.Me.Fake.fake_user!()
  #   name = "test circle"
  #   assert {:ok, circle} = Circles.create(user, name)

  #   assert circles = Circles.list_visible(user)
  #   |> debug("visicircles")
  #   assert is_list(circles) and length(circles) > 0

  #   my_circle = List.first(circles)
  #   my_circle = Repo.maybe_preload(my_circle, [:named, :caretaker])

  #   assert name == my_circle.named.name
  #   assert user.id == my_circle.caretaker.caretaker_id
  # end

  test "cannot list circles which I am not permitted to see" do
    me = Bonfire.Me.Fake.fake_user!()
    user = Bonfire.Me.Fake.fake_user!()
    name = "test circle by other user"
    assert {:ok, circle} = Circles.create(user, name)

    assert circles =
             Circles.list_visible(me)
             |> Repo.preload([:named, :caretaker])

    # debug(circles)
    assert length(circles) == 0
  end

  test "can create a circle and add people to it" do
    # create a bunch of users
    account = fake_account!()
    me = Bonfire.Me.Fake.fake_user!(account)
    alice = Bonfire.Me.Fake.fake_user!(account)
    bob = Bonfire.Me.Fake.fake_user!(account)
    carl = Bonfire.Me.Fake.fake_user!(account)

    # create a circle with alice and bob
    {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
    {:ok, _} = Circles.add_to_circles(alice, circle)
    {:ok, _} = Circles.add_to_circles(bob, circle)

    assert Bonfire.Boundaries.Circles.is_encircled_by?(alice, circle)
    assert Bonfire.Boundaries.Circles.is_encircled_by?(bob, circle)
    refute Bonfire.Boundaries.Circles.is_encircled_by?(carl, circle)
  end

  test "deleting a circle works" do
    user = Bonfire.Me.Fake.fake_user!()
    circles = Circles.list_my(user)
    assert {:ok, _} = Circles.delete(List.first(circles), current_user: user)
  end
end
