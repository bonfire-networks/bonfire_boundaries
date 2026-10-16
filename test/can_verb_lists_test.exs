defmodule Bonfire.Boundaries.CanVerbListsTest do
  @moduledoc """
  What `can?/4` means given several verbs, several objects, or `{:any, list}`.

  A list means ALL of them: every verb on every object. `{:any, list}` means at least one. Each is asked twice, of the object (answered by a query) and of the subject's loaded boundary on it (answered in memory, as templates do), and the two must agree.
  """
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.{Acls, Circles, Grants}
  alias Bonfire.Me.Fake
  alias Bonfire.Posts

  # a post whose boundary is an ACL holding exactly these grants
  defp post_with_grants(grants) do
    author = Fake.fake_user!()
    {:ok, acl} = Acls.simple_create(author, "just these")

    for {subject, verbs, value} <- grants,
        do: Grants.grant(id(subject), acl.id, verbs, value, current_user: author)

    {:ok, post} =
      Posts.publish(
        current_user: author,
        post_attrs: %{post_content: %{html_body: "a post"}},
        boundary: acl.id
      )

    post
  end

  defp local, do: Circles.get_id!(:local)

  # the same question of the object and of the subject's loaded boundary, which must agree
  defp both(subject, verbs, object) do
    loaded = Boundaries.boundaries_on_objects([id(object)], subject) |> Map.get(id(object))

    by_query = Boundaries.can?(subject, verbs, object) == true
    in_memory = Boundaries.can?(subject, verbs, loaded) == true

    assert by_query == in_memory,
           "the query says #{by_query} and the loaded boundary #{in_memory} for #{inspect(verbs)}"

    by_query
  end

  describe "a list of verbs" do
    test "means all of them" do
      reader = Fake.fake_user!()
      # readable through its link, not to be found: the shape of an unlisted post
      post = post_with_grants([{local(), [:read], true}])

      assert both(reader, [:read], post), "control: they may read it"
      refute both(reader, [:see], post), "control: but not find it"

      refute both(reader, [:see, :read], post)
    end

    test "passes when every one is granted" do
      reader = Fake.fake_user!()
      post = post_with_grants([{local(), [:see, :read], true}])

      assert both(reader, [:see, :read], post)
    end

    test "fails when one is denied, though the others are granted" do
      reader = Fake.fake_user!()
      post = post_with_grants([{local(), [:see, :read], true}, {reader, [:read], false}])

      refute both(reader, [:see, :read], post)
    end
  end

  describe "{:any, verbs}" do
    test "passes on either verb" do
      author_like = Fake.fake_user!()
      moderator_like = Fake.fake_user!()

      post =
        post_with_grants([
          {author_like, [:see, :read, :grant], true},
          {moderator_like, [:see, :read, :mediate], true}
        ])

      assert both(author_like, {:any, [:grant, :mediate]}, post)
      assert both(moderator_like, {:any, [:grant, :mediate]}, post)
    end

    test "fails when none is granted" do
      reader = Fake.fake_user!()
      post = post_with_grants([{local(), [:see, :read], true}])

      refute both(reader, {:any, [:grant, :mediate]}, post)
    end

    # each verb judged on its own: denying one does not veto another
    test "passes on a granted verb though another is denied" do
      moderator_like = Fake.fake_user!()

      post =
        post_with_grants([
          {moderator_like, [:see, :read, :mediate], true},
          {moderator_like, [:grant], false}
        ])

      refute both(moderator_like, [:grant], post), "control: :grant is denied"

      assert both(moderator_like, {:any, [:grant, :mediate]}, post)
    end
  end

  describe "several objects" do
    setup do
      reader = Fake.fake_user!()
      readable = post_with_grants([{local(), [:see, :read], true}])
      unreadable = post_with_grants([])

      {:ok, reader: reader, readable: readable, unreadable: unreadable}
    end

    test "a list means all of them", %{reader: reader, readable: readable, unreadable: unreadable} do
      assert Boundaries.can?(reader, :read, [readable]), "control: the one they may read"
      refute Boundaries.can?(reader, :read, [readable, unreadable])
    end

    test "{:any, objects} means at least one", %{
      reader: reader,
      readable: readable,
      unreadable: unreadable
    } do
      assert Boundaries.can?(reader, :read, {:any, [readable, unreadable]})
      refute Boundaries.can?(reader, :read, {:any, [unreadable]})
    end

    # the creator shortcut used to look at the first object only, passing the whole list unchecked
    test "having created the first does not pass the others", %{unreadable: unreadable} do
      creator = Fake.fake_user!()

      {:ok, own} =
        Posts.publish(
          current_user: creator,
          post_attrs: %{post_content: %{html_body: "mine"}},
          boundary: "mentions"
        )

      assert Boundaries.can?(creator, :read, [own]), "control: their own post"
      refute Boundaries.can?(creator, :read, [own, unreadable])
    end
  end

  test "{:any, subjects} is not supported yet" do
    post = post_with_grants([{local(), [:see, :read], true}])

    assert_raise RuntimeError, ~r/not supported/, fn ->
      Boundaries.can?({:any, [Fake.fake_user!(), Fake.fake_user!()]}, :read, post)
    end
  end
end
