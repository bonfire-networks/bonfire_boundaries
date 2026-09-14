defmodule Bonfire.Boundaries.ObjectBoundarisedFunctionTest do
  @moduledoc """
  `Queries.object_boundarised/2` is the FUNCTION form of boundarising, and it exists for callers that cannot use the `boundarise/3` macro: `Bonfire.Common.Needles` reaches it through `maybe_apply/4` because requiring the macro there would be a dependency cycle. Two properties of that arrangement are worth holding still.

  The reach: `maybe_apply/4` is called with `fallback_return: q`, so if the module ever fails to resolve, the UNBOUNDARISED query is what comes back. `Needles.one/2` and `Needles.many/2` are the public doors onto it, so they are asserted directly rather than through the function they delegate to.

  The `:admins` flag: `skip_boundary_check` is three-valued (`true | :admins | false`), and `:admins` means "skip these checks FOR an admin" rather than "skip these checks". It has to be resolved by asking `is_admin?/1`, since a plain truthiness test hands every caller the bypass.

  Each refusal is paired with the case that must still work. On its own, "they could not see it" is indistinguishable from boundaries applying unconditionally, which would make these paths useless rather than dangerous.
  """
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  import Ecto.Query
  alias Bonfire.Boundaries.Queries
  alias Bonfire.Common.Needles
  alias Bonfire.Posts
  alias Bonfire.Me.Fake

  defp mentions_only_post(author) do
    assert {:ok, post} =
             Posts.publish(
               current_user: author,
               post_attrs: %{post_content: %{html_body: "for nobody else"}},
               boundary: "mentions"
             )

    post
  end

  describe "through Bonfire.Common.Needles, which reaches it via maybe_apply" do
    test "one/2 refuses an object the viewer may not read, and returns it to one who may" do
      author = Fake.fake_user!()
      stranger = Fake.fake_user!()
      post = mentions_only_post(author)

      assert {:ok, _} = Needles.one(post.id, current_user: author)

      assert {:error, _} = Needles.one(post.id, current_user: stranger)
    end

    test "many/2 omits objects the viewer may not read, and includes ones they may" do
      author = Fake.fake_user!()
      stranger = Fake.fake_user!()
      post = mentions_only_post(author)

      assert {:ok, mine} = Needles.many([id: post.id], current_user: author)
      assert Enum.any?(mine, &(&1.id == post.id))

      assert {:ok, theirs} = Needles.many([id: post.id], current_user: stranger)
      refute Enum.any?(theirs, &(&1.id == post.id))
    end
  end

  describe "the :admins value of skip_boundary_check" do
    defp visible_ids(subject) do
      from(p in Bonfire.Data.Social.Post, as: :main_object)
      |> Queries.object_boundarised(current_user: subject, skip_boundary_check: :admins)
      |> repo().all()
      |> Enum.map(& &1.id)
      |> MapSet.new()
    end

    test "bypasses for an admin, and for nobody else" do
      author = Fake.fake_user!()
      stranger = Fake.fake_user!()
      {:ok, admin} = Bonfire.Me.Users.make_admin(Fake.fake_user!())
      post = mentions_only_post(author)

      refute MapSet.member?(visible_ids(stranger), post.id),
             "an ordinary user passing the flag must still be boundarised"

      assert MapSet.member?(visible_ids(admin), post.id),
             "an admin passing the flag gets the bypass the flag is named for"
    end
  end
end
