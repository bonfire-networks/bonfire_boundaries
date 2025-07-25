defmodule Bonfire.Boundaries.PostBoundariesTest do
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  import Bonfire.Boundaries.Debug
  alias Bonfire.Me.Fake
  alias Bonfire.Posts
  alias Bonfire.Social.FeedActivities
  alias Bonfire.Boundaries

  test "creating & then reading my own post" do
    user = Bonfire.Me.Fake.fake_user!()

    attrs = %{
      post_content: %{
        summary: "summary",
        html_body: "<p>epic html message</p>"
      }
    }

    assert {:ok, post} = Posts.publish(current_user: user, post_attrs: attrs)
    assert String.contains?(post.post_content.html_body, "epic html message")
    assert post.post_content.summary =~ "summary"

    assert {:ok, post} = Posts.read(post.id, current_user: user)
    assert post.post_content.summary =~ "summary"
  end

  test "cannot read posts which I am not permitted to see" do
    user = Bonfire.Me.Fake.fake_user!()

    attrs = %{
      post_content: %{
        summary: "summary",
        html_body: "<p>epic html message</p>"
      }
    }

    assert {:ok, post} = Posts.publish(current_user: user, post_attrs: attrs)
    assert post.post_content.summary =~ "summary"

    # debug_object_acls(post)

    me = Bonfire.Me.Fake.fake_user!()
    assert {:error, :not_found} = Posts.read(post.id, me)
  end

  test "creating & then seeing my own post in my outbox feed" do
    user = Bonfire.Me.Fake.fake_user!()

    attrs = %{
      post_content: %{
        summary: "summary",
        html_body: "<p>epic html message</p>"
      }
    }

    assert {:ok, post} =
             Posts.publish(
               current_user: user,
               post_attrs: attrs,
               boundary: "local"
             )

    assert post.post_content.summary =~ "summary"

    assert Bonfire.Social.FeedLoader.feed_contains?(:user_activities, post,
             current_user: user,
             by: user
           )
  end

  test "cannot see posts I'm not allowed to see in instance feed" do
    user = Bonfire.Me.Fake.fake_user!()

    attrs = %{
      post_content: %{
        summary: "summary",
        html_body: "<p>epic html message</p>"
      }
    }

    assert {:ok, post} = Posts.publish(current_user: user, post_attrs: attrs)
    assert post.post_content.summary =~ "summary"

    me = Bonfire.Me.Fake.fake_user!()
    refute Bonfire.Social.FeedLoader.feed_contains?(:local, post, current_user: me)
  end
end
