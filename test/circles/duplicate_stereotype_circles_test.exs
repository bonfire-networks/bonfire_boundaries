defmodule Bonfire.Boundaries.Circles.DuplicateStereotypeCirclesTest do
  @moduledoc """
  A caretaker with two circles of one stereotype (two jobs each read none and made one at the same time, since nothing keeps them unique) gets `{:error, "Unexpected number of stereotypes"}` from `Circles.get_or_create_stereotype_circle/2` on every later call.

  The data migration keeps the earliest circle of each caretaker and stereotype, moves the members of the others into it, and deletes the others.
  """
  use Bonfire.Boundaries.DataCase, async: false

  import Ecto.Query
  import Bonfire.Me.Fake

  @moduletag :backend

  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Scaffold.DuplicateStereotypeCirclesDataMigration
  alias Bonfire.Data.AccessControl.Circle
  alias Bonfire.Data.AccessControl.Encircle

  defp run_migration do
    DuplicateStereotypeCirclesDataMigration.base_query()
    |> repo().all()
    |> DuplicateStereotypeCirclesDataMigration.migrate()
  end

  defp members(circle_id),
    do: repo().all(from(e in Encircle, where: e.circle_id == ^circle_id, select: e.subject_id))

  defp circle_exists?(circle_id),
    do: repo().exists?(from(c in Circle, where: c.id == ^circle_id))

  # the user already has a `:silence_me` circle from signup, so this makes a second one
  defp with_duplicate(user, members) do
    [first] = Circles.get_stereotype_circles(user, [:silence_me])
    assert {:ok, second} = Circles.create_stereotype_circle(user, :silence_me)
    assert first.id < second.id

    Enum.each(members, fn {circle, subject} ->
      assert {:ok, _} =
               Circles.add_to_circles(subject, if(circle == :first, do: first, else: second))
    end)

    {first, second}
  end

  test "the earliest circle is kept, with the members of the others, and the others are deleted" do
    user = fake_user!()
    in_first = fake_user!()
    in_second = fake_user!()
    in_both = fake_user!()

    {first, second} =
      with_duplicate(user, [
        {:first, in_first},
        {:second, in_second},
        {:first, in_both},
        {:second, in_both}
      ])

    assert {:error, _} = Circles.get_or_create_stereotype_circle(user, :silence_me)

    run_migration()

    assert [kept] = Circles.get_stereotype_circles(user, [:silence_me])
    assert kept.id == first.id
    refute circle_exists?(second.id)

    assert Enum.sort(members(first.id)) == Enum.sort([in_first.id, in_second.id, in_both.id])
    assert members(second.id) == []

    assert {:ok, %{id: id}} = Circles.get_or_create_stereotype_circle(user, :silence_me)
    assert id == first.id
  end

  test "the circles of other caretakers are left alone" do
    user = fake_user!()
    other = fake_user!()
    [others_circle] = Circles.get_stereotype_circles(other, [:silence_me])
    with_duplicate(user, [])

    run_migration()

    assert [%{id: id}] = Circles.get_stereotype_circles(other, [:silence_me])
    assert id == others_circle.id
  end

  test "running it again changes nothing" do
    user = fake_user!()
    in_second = fake_user!()
    {first, _second} = with_duplicate(user, [{:second, in_second}])

    run_migration()
    assert DuplicateStereotypeCirclesDataMigration.base_query() |> repo().all() == []

    run_migration()
    assert members(first.id) == [in_second.id]
  end
end
