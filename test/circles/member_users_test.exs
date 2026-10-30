defmodule Bonfire.Boundaries.Circles.MemberUsersTest do
  @moduledoc """
  The members of a circle as users, in one query, with their character loaded (what a notification feed is looked up from). `list_members/2` returns the `Encircle` rows instead, with the subject unloaded.
  """
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries.Circles
  alias Bonfire.Data.Identity.User
  alias Bonfire.Me.Fake

  test "lists the users in a circle with their character loaded, and nobody else" do
    owner = Fake.fake_user!()
    member = Fake.fake_user!()
    other_member = Fake.fake_user!()
    outsider = Fake.fake_user!()
    assert {:ok, circle} = Circles.create(owner, "regulars")
    assert {:ok, _} = Circles.add_to_circles(member, circle)
    assert {:ok, _} = Circles.add_to_circles(other_member, circle)

    users = Circles.list_member_users(circle)

    assert Enum.sort(Enum.map(users, & &1.id)) == Enum.sort([member.id, other_member.id])
    refute outsider.id in Enum.map(users, & &1.id)

    assert Enum.all?(users, fn
             %User{character: %{} = character} -> Ecto.assoc_loaded?(character.peered)
             _ -> false
           end)
  end

  test "a circle with no members lists none" do
    owner = Fake.fake_user!()
    assert {:ok, circle} = Circles.create(owner, "nobody")

    assert Circles.list_member_users(circle) == []
  end

  test "takes the id of a circle too" do
    owner = Fake.fake_user!()
    member = Fake.fake_user!()
    assert {:ok, circle} = Circles.create(owner, "regulars")
    assert {:ok, _} = Circles.add_to_circles(member, circle)

    assert [%User{id: id}] = Circles.list_member_users(circle.id)
    assert id == member.id
  end
end
