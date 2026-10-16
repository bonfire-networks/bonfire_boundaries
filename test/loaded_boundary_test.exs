defmodule Bonfire.Boundaries.LoadedBoundaryTest do
  @moduledoc """
  A loaded boundary (`boundaries_on_objects/2`, `boundary_on_object/2`) is what templates ask `can?/3` with, to save a query per check, so it must answer as asking about the object itself would.

  For a viewer with no grants of their own to load, a guest for one, it was the object's preset ACL alone, and `can?/3`, finding no verbs in it, asked the database about the ACL's id instead of the object's.
  """
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries
  alias Bonfire.Me.Fake
  alias Bonfire.Posts

  setup do
    {:ok, post} =
      Posts.publish(
        current_user: Fake.fake_user!(),
        post_attrs: %{post_content: %{html_body: "for everyone"}},
        boundary: "public"
      )

    {:ok, post: post}
  end

  test "a guest's, from several objects, answers about the object", %{post: post} do
    loaded = Boundaries.boundaries_on_objects([id(post)], nil) |> Map.get(id(post))

    assert Boundaries.can?(nil, :read, post), "control: a guest may read a public post"

    assert Boundaries.can?(nil, :read, loaded) == true
  end

  test "a guest's, from one object, answers about the object", %{post: post} do
    loaded = Boundaries.boundary_on_object(id(post), nil)

    assert Boundaries.can?(nil, :read, loaded) == true
  end

  test "a user's with grants answers in memory, as before", %{post: post} do
    reader = Fake.fake_user!()
    loaded = Boundaries.boundaries_on_objects([id(post)], reader) |> Map.get(id(post))

    assert Boundaries.can?(reader, :read, loaded) == true
    refute Boundaries.can?(reader, :delete, loaded), "and refuses what they may not do"
  end
end
