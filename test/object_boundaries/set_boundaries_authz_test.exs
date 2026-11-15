defmodule Bonfire.Boundaries.SetBoundariesAuthzTest do
  @moduledoc """
  `Boundaries.set_boundaries/3` changes who can see an object, so the acting user has to be allowed to configure it (its creator, its caretaker, or someone granted `:configure`), unless the caller has checked already and says so.
  """
  use Bonfire.Boundaries.DataCase, async: false
  @moduletag :backend

  import Ecto.Query
  alias Bonfire.Me.Fake
  alias Bonfire.Posts

  defp acl_ids(post),
    do:
      Bonfire.Common.Repo.all(
        from(c in Bonfire.Data.AccessControl.Controlled,
          where: c.id == ^post.id,
          select: c.acl_id
        )
      )
      |> Enum.sort()

  setup do
    owner = Fake.fake_user!()
    stranger = Fake.fake_user!()

    {:ok, post} =
      Posts.publish(
        current_user: owner,
        post_attrs: %{post_content: %{html_body: "Someone's public post"}},
        boundary: "public"
      )

    {:ok, owner: owner, stranger: stranger, post: post}
  end

  test "someone who can't configure a post can't make it private", %{
    stranger: stranger,
    post: post
  } do
    before = acl_ids(post)
    assert before != [], "control: the post has ACLs to begin with"

    assert {:error, :not_permitted} =
             Bonfire.Boundaries.set_boundaries(stranger, post, to_boundaries: "private")

    assert acl_ids(post) == before
  end

  test "someone who can't configure a post can't replace its preset", %{
    stranger: stranger,
    post: post
  } do
    before = acl_ids(post)

    assert {:error, :not_permitted} =
             Bonfire.Boundaries.set_boundaries(stranger, post,
               boundary: "mentions",
               remove_previous_preset: "public"
             )

    assert acl_ids(post) == before
  end

  test "the post's creator can make it private (control)", %{owner: owner, post: post} do
    assert {:ok, _} = Bonfire.Boundaries.set_boundaries(owner, post, to_boundaries: "private")
    assert acl_ids(post) == []
  end

  test "a caller that has checked already can say so", %{stranger: stranger, post: post} do
    assert {:ok, _} =
             Bonfire.Boundaries.set_boundaries(stranger, post,
               to_boundaries: "private",
               skip_boundary_check: true
             )

    assert acl_ids(post) == []
  end
end
