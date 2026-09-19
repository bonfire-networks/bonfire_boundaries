defmodule Bonfire.Boundaries.QueriesUsersGrantsBatchTest do
  @moduledoc """
  `Boundaries.users_grants_on/3` must answer for SEVERAL subjects the same way it does for one.

  It is the only batch permission check in the codebase, which is what makes it the right tool when deciding something for a set of people at once (notification fan-out asks "which of these can still see this object?", and a check per person is the `follows?/2` N+1 mistake).

  Asking about several people answers as asking about each of them would, which is what makes it usable for "which of these can see this object?": each permitted person is named by their own id, and each subject's locality circle (`:local` / `:activity_pub`) is expanded too, since subjects in one list can differ in locality and much content is granted to a circle rather than to people directly. Each subject needs `:peered` loaded to be classifiable, as it does on its own.

  See `queries_subject_circles_test.exs` for how a single subject is expanded.
  """
  use Bonfire.DataCase, async: false

  use Bonfire.Common.E

  alias Bonfire.Boundaries
  alias Bonfire.Me.Fake

  setup do
    alice = Fake.fake_user!()
    bob = Fake.fake_user!()
    carol = Fake.fake_user!()

    {:ok, post} =
      Bonfire.Posts.publish(
        current_user: alice,
        post_attrs: %{post_content: %{html_body: "a public post"}},
        boundary: "public"
      )

    {:ok, alice: alice, bob: bob, carol: carol, post: post}
  end

  defp permitted_ids(subjects, object) do
    Boundaries.users_grants_on(subjects, object, [:see, :read])
    |> Enum.map(&e(&1, :subject_id, nil))
    |> Enum.uniq()
  end

  test "one subject may see a public post", %{bob: bob, post: post} do
    assert permitted_ids(bob, post) != [], "a local user can see a public post"
  end

  test "a list of subjects names the same people as asking about each alone", %{
    bob: bob,
    carol: carol,
    post: post
  } do
    together = permitted_ids([bob, carol], post)

    assert together != [], "a batch check must not answer 'nobody' for a post they can all see"

    for user <- [bob, carol] do
      assert user.id in together
      assert user.id in permitted_ids(user, post)
    end
  end

  test "a list gets each subject's locality circle, as a single subject does", %{
    bob: bob,
    carol: carol,
    post: post
  } do
    # most content is granted to a locality circle rather than to people, so a batch check has to expand subjects the same way a single one does
    local_circle = Bonfire.Boundaries.Circles.get_id!(:local)

    assert local_circle in permitted_ids(bob, post)
    assert local_circle in permitted_ids([bob, carol], post)
  end

  test "denying the local circle takes the permission away from local people", %{
    alice: alice,
    bob: bob,
    carol: carol,
    post: post
  } do
    # a local person's permission on public content comes through the `:local` circle, so denying that circle has to reach them: this is the shape a hide/block relies on (`Blocks.hide/3` grants `:cannot_discover` the same way)
    assert bob.id in permitted_ids([bob, carol], post)

    {:ok, acl} = Bonfire.Boundaries.Acls.get_or_create_object_custom_acl(post, alice)

    Bonfire.Boundaries.Grants.grant_role(
      Bonfire.Boundaries.Circles.get_id!(:local),
      acl,
      :cannot_discover,
      current_user: alice
    )

    refute bob.id in permitted_ids([bob, carol], post)
  end

  test "a subject who cannot see the object is absent from the batch answer", %{
    alice: alice,
    bob: bob,
    carol: carol
  } do
    {:ok, private} =
      Bonfire.Posts.publish(
        current_user: alice,
        post_attrs: %{post_content: %{html_body: "only for me"}},
        boundary: "mentions"
      )

    assert permitted_ids([bob, carol], private) == []
  end
end
