defmodule Bonfire.Boundaries.WebBoundariesTests do
  use Bonfire.Social.DataCase, async: true
  import Bonfire.Boundaries.Debug
  alias Bonfire.Me.Fake
  alias Bonfire.Social.{Posts, Follows Likes, Boosts}
  alias Bonfire.Social.FeedActivities
  alias Bonfire.Boundaries

  test "creating a post with a 'public' boundary and verify that all users can see and interact with it" do
    account = fake_account!()
    # Given a user
    alice = fake_user!(account)
    # And another user that I follow
    bob = fake_user!(account)
    Follows.follow(alice, bob)
    # When I login as Alice
    conn = conn(user: alice, account: account)
    # And bob creates a post with a 'public' boundary
    attrs = %{
      post_content: %{
        html_body: "<p>epic html message</p>",
        boundary: "public"
      }
    }

    assert {:ok, post} = Posts.publish(current_user: bob, post_attrs: attrs)
    {:ok, view, _html} = live(conn, "/")
    # assert I can see the post in my feed
    assert view.feed_posts |> Enum.any?(&(&1.id == post.id))
    # And I can read the post
    assert {:ok, _post} = Posts.read(post.id, current_user: alice)
    # And I can like the post
    assert {:ok, _post} = Likes.like(alice, post)
    # And I can boost the post
    assert {:ok, _boost} = Boosts.boost(alice, post)
    # And I can reply to the post
    attrs_reply = %{
      post_content: %{
        html_body: "<p>epic reply</p>"
      },
      reply_to_id: post.id
    }

    assert {:ok, _post_reply} = Posts.publish(
                                  current_user: alice,
                                  post_attrs: attrs_reply,
                                  boundary: "public"
                                )

    # And I can see the post in bob's profile
    {:ok, view, _html} = live(conn, "/#{bob.username}")
    assert view.profile_posts |> Enum.any?(&(&1.id == post.id))

  end

  test "creating a post with a 'local' boundary and verify that only users from that instance can see and interact with it." do
  end

  test "creating a post with a 'mention' boundary and verify that only mentioned users can see and interact with it." do
  end

  test "Test creating a post with a 'custom' boundary and verify that only specified users or circles can see and interact with it according to their assigned roles." do
  end

  test "Test adding a user with a 'see' role and verify that the user can see the post but not interact with it." do
  end

  test "adding a user with a 'read' role and verify that the user can read the post's content but not interact with it." do
  end

  test "adding a user with an 'interact' role and verify that the user can like and boost the post." do
  end

  test "adding a user with a 'participate' role and verify that the user can engage in the post's activities and discussions." do
  end

  test "adding a user with a 'caretaker' role and verify that the user can delete the post" do
  end

  test "adding a user with a 'none' role and verify that the user cannot see or interact with the post in any way." do
  end

  test "creating a post with a circle, and verify that only users within the circle can access the post according to their assigned roles." do
  end

  test "creating a post with a custom boundary, and verify that only users within the boundary can access the post according to their assigned roles." do
  end
end
