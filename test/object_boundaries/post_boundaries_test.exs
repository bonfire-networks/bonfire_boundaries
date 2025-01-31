defmodule Bonfire.Boundaries.PostBoundariesTest do
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  import Bonfire.Boundaries.Debug
  alias Bonfire.Me.Fake
  alias Bonfire.Posts
  alias Bonfire.Social.FeedActivities
  alias Bonfire.Boundaries

  test "creating & then reading my own post" do
    user = fake_user!()

    attrs = %{
      post_content: %{
        summary: "summary",
        name: "name",
        html_body: "<p>epic html message</p>"
      }
    }

    assert {:ok, post} = Posts.publish(current_user: user, post_attrs: attrs)
    assert String.contains?(post.post_content.html_body, "epic html message")
    assert post.post_content.name =~ "name"

    assert {:ok, post} = Posts.read(post.id, current_user: user)
    assert post.post_content.name =~ "name"
  end

  test "cannot read posts which I am not permitted to see" do
    user = fake_user!()

    attrs = %{
      post_content: %{
        summary: "summary",
        name: "name",
        html_body: "<p>epic html message</p>"
      }
    }

    assert {:ok, post} = Posts.publish(current_user: user, post_attrs: attrs)
    assert post.post_content.name =~ "name"

    # debug_object_acls(post)

    me = fake_user!()
    assert {:error, :not_found} = Posts.read(post.id, me)
  end

  test "creating & then seeing my own post in my outbox feed" do
    user = fake_user!()

    attrs = %{
      post_content: %{
        summary: "summary",
        name: "name",
        html_body: "<p>epic html message</p>"
      }
    }

    assert {:ok, post} =
             Posts.publish(
               current_user: user,
               post_attrs: attrs,
               boundary: "local"
             )

    assert post.post_content.name =~ "name"

    feed_id = Bonfire.Social.Feeds.feed_id(:outbox, user)

    assert Bonfire.Social.FeedLoader.feed_contains?(:outbox, post, current_user: user)
  end

  test "cannot see posts I'm not allowed to see in instance feed" do
    user = fake_user!()

    attrs = %{
      post_content: %{
        summary: "summary",
        name: "name",
        html_body: "<p>epic html message</p>"
      }
    }

    assert {:ok, post} = Posts.publish(current_user: user, post_attrs: attrs)
    assert post.post_content.name =~ "name"

    me = fake_user!()
    refute Bonfire.Social.FeedLoader.feed_contains?(:local, post, current_user: me)
  end
end
