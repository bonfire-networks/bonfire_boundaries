defmodule Bonfire.Boundaries.CanIncludeDeletedTest do
  @moduledoc """
  `Bonfire.Boundaries.can?/4` leaves out soft-deleted objects (their pointer's `deleted_at` is set), so asking about one answers false. Code that manages soft-deleted things, eg. restoring an archived group, asks with `include_deleted: true`, which keeps the object's own boundaries in force rather than skipping them.
  """

  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries
  alias Bonfire.Me.Fake

  # someone other than the author, who is always permitted on what they created
  setup do
    author = Fake.fake_user!()
    reader = Fake.fake_user!()

    {:ok, post} =
      Bonfire.Posts.publish(
        current_user: author,
        post_attrs: %{post_content: %{html_body: "<p>soon gone</p>"}},
        boundary: "public"
      )

    {:ok, reader: reader, post: post}
  end

  test "can? answers for a soft-deleted object when asked to include deleted ones", %{
    reader: reader,
    post: post
  } do
    assert Boundaries.can?(reader, :read, post), "control: anyone may read a public post"

    assert {:ok, _} = Bonfire.Common.Repo.Delete.soft_delete(post)

    refute Boundaries.can?(reader, :read, post),
           "control: a soft-deleted object is left out by default"

    assert Boundaries.can?(reader, :read, post, include_deleted: true),
           "asked to include deleted objects, the post's own boundaries still answer"
  end

  test "including deleted objects doesn't skip their boundaries", %{reader: reader, post: post} do
    assert {:ok, _} = Bonfire.Common.Repo.Delete.soft_delete(post)

    refute Boundaries.can?(reader, :edit, post, include_deleted: true),
           "a reader may not edit someone else's post, deleted or not"
  end
end
