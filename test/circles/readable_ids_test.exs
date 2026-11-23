defmodule Bonfire.Boundaries.Circles.ReadableIdsTest do
  @moduledoc "A circle filter (a feed narrowed to a circle's members) only takes circles the reader may read: anyone else's list or block circle would show who is in it, through whose posts come back. One check for the web feed's `set_filter` and the GraphQL feed."
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries.Circles
  alias Bonfire.Me.Fake

  test "keeps the reader's own circles and drops someone else's" do
    me = Fake.fake_user!()
    other = Fake.fake_user!()
    {:ok, mine} = Circles.create(me, %{named: %{name: "mine"}})
    {:ok, theirs} = Circles.create(other, %{named: %{name: "theirs"}})

    assert Circles.readable_ids([mine.id, theirs.id], me) == [mine.id]
  end

  test "drops another person's block circle" do
    me = Fake.fake_user!()
    other = Fake.fake_user!()
    {:ok, _} = Bonfire.Boundaries.Blocks.block(Fake.fake_user!(), :silence, current_user: other)
    [silence_circle] = Circles.stereotype_circle_ids_for(other, [:silence_them])

    assert Circles.readable_ids([silence_circle], me) == []
  end

  # as `get/2`: a guest opens a circle shared publicly (the circle page), not a private one
  test "a guest reads only circles shared publicly, and junk is dropped" do
    other = Fake.fake_user!()
    {:ok, theirs} = Circles.create(other, %{named: %{name: "theirs"}})
    {:ok, shared} = Circles.create(other, %{named: %{name: "shared"}})
    Bonfire.Boundaries.set_boundaries(other, shared, boundary: "public")

    assert Circles.readable_ids([theirs.id, shared.id], nil) == [shared.id]
    assert Circles.readable_ids(["not an id", nil], other) == []
  end
end
