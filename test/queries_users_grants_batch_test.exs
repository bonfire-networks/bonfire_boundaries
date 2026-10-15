defmodule Bonfire.Boundaries.QueriesUsersGrantsBatchTest do
  @moduledoc """
  Batch permission checks must answer for SEVERAL subjects the same way they do for one.

  `Boundaries.permitted_users/3` is the one to decide something for a set of people at once (notification fan-out asks "which of these can still see this object?", and a check per person is the `follows?/2` N+1 mistake): it returns the people, with `can?/3`'s rules for each. `Boundaries.users_grants_on/3` returns their grants instead, and is tested here for how it expands subjects.

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

  # who may see and read it
  defp permitted_ids(subjects, object) do
    Boundaries.permitted_users(subjects, [:see, :read], object)
    |> Enum.map(&id/1)
  end

  # whose grants on it are found, which names a locality circle as well as people
  defp grant_subject_ids(subjects, object) do
    Boundaries.users_grants_on(subjects, object)
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

    assert local_circle in grant_subject_ids(bob, post)
    assert local_circle in grant_subject_ids([bob, carol], post)
  end

  test "denying the local circle takes the permission away from local people", %{
    alice: alice,
    bob: bob,
    carol: carol,
    post: post
  } do
    # a local person's permission on public content comes through the `:local` circle, so denying that circle has to reach them: this is the shape a hide/block relies on (`Blocks.hide/3` grants `:can_only_read` the same way)
    assert bob.id in permitted_ids([bob, carol], post)

    {:ok, acl} = Bonfire.Boundaries.Acls.get_or_create_object_custom_acl(post, alice)

    Bonfire.Boundaries.Grants.grant_role(
      Bonfire.Boundaries.Circles.get_id!(:local),
      acl,
      :can_only_read,
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

  # the same question answered in SQL, with `can?/3`'s rules for each person: their own grants pooled with their locality circle's, EVERY verb asked about, and a denial winning. It returns the people, not their grants
  describe "permitted_users/3" do
    defp permitted_users(users, verbs, object),
      do: Boundaries.permitted_users(users, verbs, object) |> Enum.map(&id/1) |> Enum.sort()

    test "names each of several people who may see and read a public post", %{
      bob: bob,
      carol: carol,
      post: post
    } do
      assert permitted_users([bob, carol], [:see, :read], post) == Enum.sort([bob.id, carol.id])
    end

    test "leaves out someone denied it themselves, and keeps the others", %{
      alice: alice,
      bob: bob,
      carol: carol,
      post: post
    } do
      {:ok, acl} = Bonfire.Boundaries.Acls.get_or_create_object_custom_acl(post, alice)
      Bonfire.Boundaries.Grants.grant(bob.id, acl.id, [:see, :read], false, current_user: alice)

      refute Boundaries.can?(bob, :read, post), "control: the denial took"

      assert permitted_users([bob, carol], [:see, :read], post) == [carol.id]
    end

    test "leaves out local people once their circle is denied it", %{
      alice: alice,
      bob: bob,
      carol: carol,
      post: post
    } do
      {:ok, acl} = Bonfire.Boundaries.Acls.get_or_create_object_custom_acl(post, alice)

      Bonfire.Boundaries.Grants.grant_role(
        Bonfire.Boundaries.Circles.get_id!(:local),
        acl,
        :can_only_read,
        current_user: alice
      )

      assert permitted_users([bob, carol], [:see, :read], post) == []
    end

    # readable through a link but not to be found, which `:see` AND `:read` must not count as visible
    test "needs every verb asked about", %{alice: alice, bob: bob} do
      {:ok, acl} = Bonfire.Boundaries.Acls.simple_create(alice, "locals may read, not find")

      Bonfire.Boundaries.Grants.grant(
        Bonfire.Boundaries.Circles.get_id!(:local),
        acl.id,
        [:read],
        true,
        current_user: alice
      )

      {:ok, unlisted} =
        Bonfire.Posts.publish(
          current_user: alice,
          post_attrs: %{post_content: %{html_body: "read it if you have the link"}},
          boundary: acl.id
        )

      assert permitted_users([bob], [:read], unlisted) == [bob.id], "control: bob may read it"
      assert permitted_users([bob], [:see, :read], unlisted) == []
    end

    test "names nobody for a post none of them may see", %{alice: alice, bob: bob, carol: carol} do
      {:ok, private} =
        Bonfire.Posts.publish(
          current_user: alice,
          post_attrs: %{post_content: %{html_body: "only for me"}},
          boundary: "mentions"
        )

      assert permitted_users([bob, carol], [:see, :read], private) == []
    end

    test "names nobody when asked about nobody", %{post: post} do
      assert permitted_users([], [:see, :read], post) == []
    end
  end

  # the circles themselves as subjects, each answering for itself alone: what federation's interaction policy asks (`filter_circles_who_can/4`), eg. whether remote people as a whole may reply
  describe "filter_circles_who_can/4" do
    test "names the circles granted the verb on a public post", %{post: post} do
      local = Bonfire.Boundaries.Circles.get_id!(:local)
      activity_pub = Bonfire.Boundaries.Circles.get_id!(:activity_pub)

      assert Enum.sort(Boundaries.filter_circles_who_can([local, activity_pub], :read, post)) ==
               Enum.sort([local, activity_pub])
    end

    test "leaves out a circle denied the verb", %{alice: alice, post: post} do
      local = Bonfire.Boundaries.Circles.get_id!(:local)
      activity_pub = Bonfire.Boundaries.Circles.get_id!(:activity_pub)

      {:ok, acl} = Bonfire.Boundaries.Acls.get_or_create_object_custom_acl(post, alice)
      Bonfire.Boundaries.Grants.grant(activity_pub, acl.id, [:read], false, current_user: alice)

      assert Boundaries.filter_circles_who_can([local, activity_pub], :read, post) == [local]
    end
  end
end
