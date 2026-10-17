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

  # the two ways of loading a page's verbs (`granted_verbs_strategy`), compared on a live instance, must say the same: shared ACLs, an object's own, and denials in either
  test "per object and per ACL load the same verbs" do
    author = Fake.fake_user!()
    viewer = Fake.fake_user!()

    publish = fn boundary, extra ->
      {:ok, post} =
        Posts.publish(
          [
            current_user: author,
            post_attrs: %{
              post_content: %{
                html_body: "<p>a #{boundary} post @#{viewer.character.username}</p>"
              }
            },
            boundary: boundary
          ] ++ extra
        )

      post
    end

    public = publish.("public", [])
    local = publish.("local", [])
    mentions = publish.("mentions", [])
    locked = publish.("public", [])
    {:ok, _} = Bonfire.Boundaries.Blocks.lock(locked, current_user: author)
    hidden = publish.("public", [])
    {:ok, _} = Bonfire.Boundaries.Blocks.block(hidden, :hide, current_user: viewer)

    ids = Enum.map([public, local, mentions, locked, hidden], &id/1)

    for who <- [author, viewer, nil] do
      per_object =
        Bonfire.Boundaries.Queries.granted_verbs_on(who, ids) |> repo().all() |> MapSet.new()

      per_acl =
        Bonfire.Boundaries.Queries.granted_verbs_on_per_acl(who, ids)
        |> repo().all()
        |> MapSet.new()

      assert MapSet.size(per_object) > 0, "control: something is granted"
      assert per_acl == per_object, "#{if who, do: id(who), else: "guest"}"
    end
  end
end
