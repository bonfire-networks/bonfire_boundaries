defmodule Bonfire.Boundaries.PostBoundariesTest do
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  import Bonfire.Boundaries.Debug
  import Ecto.Query
  alias Bonfire.Me.Fake
  alias Bonfire.Posts
  alias Bonfire.Social.FeedActivities
  alias Bonfire.Boundaries

  test "creating & then reading my own post" do
    user = Bonfire.Me.Fake.fake_user!()

    # Config.get!([:object_default_boundaries, :acls])
    # |> debug("Default ACLs")

    # searched_stereotype_ids = [
    #   "71MAYADM1N1STERMY0WNSTVFFS",
    #   "2HEYS11ENCEDMES0CAN0TSEEME",
    #   "0H0STEDCANTSEE0RD0ANYTH1NG",
    #   "1S11ENCEDTHEMS0CAN0TP1NGME"
    # ]
    # |> debug("Searched stereotype IDs")

    # # Inspect ACLs for the user using Ecto
    # user_acl_ids =
    #   repo().all(
    #     from c in Bonfire.Data.Identity.Caretaker,
    #       where: c.caretaker_id == ^user.id,
    #       select: c.id
    #   )
    #   |> debug("user_acl_ids")

    # acl_query =
    #   from a in Bonfire.Data.AccessControl.Acl,
    #     where: a.id in ^user_acl_ids

    # repo().all(acl_query) |> debug("User ACLs (Ecto)")

    # caretaker_records_query =
    #   from c in Bonfire.Data.Identity.Caretaker,
    #     where: c.caretaker_id == ^user.id

    # # Inspect caretaker records for the user using Ecto
    # repo().all(caretaker_records_query)
    # |> debug("Caretaker records (Ecto)")

    # stereotype_records =
    #   repo().all(
    #     from s in Bonfire.Data.AccessControl.Stereotyped,
    #       where: s.id in ^user_acl_ids
    #   )
    #   |> debug("Stereotypes for user ACLs (Ecto)")

    # found_stereotype_ids =
    #   stereotype_records
    #   |> Enum.map(& &1.stereotype_id)
    #   |> debug("Found stereotype IDs for user ACLs")

    # intersection =
    #   Enum.filter(found_stereotype_ids, &(&1 in searched_stereotype_ids))
    #   |> debug("Intersection of searched and found stereotype IDs")

    # Bonfire.Boundaries.find_caretaker_stereotypes(user.id, intersection, Bonfire.Data.AccessControl.Acl)
    # # |> debug("Caretaker stereotypes (check)")

    attrs = %{
      post_content: %{
        summary: "summary",
        html_body: "<p>epic html message</p>"
      }
    }

    assert {:ok, post} = Posts.publish(current_user: user, post_attrs: attrs)
    assert String.contains?(post.post_content.html_body, "epic html message")
    assert post.post_content.summary =~ "summary"

    # Bonfire.Boundaries.find_caretaker_stereotypes(user.id, intersection, Bonfire.Data.AccessControl.Acl)
    # |> debug("Caretaker stereotypes (check after post creation)")

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

  describe "thread locking:" do
    test "locking a post prevents replies from other users, and unlocking allows them again" do
      author = Bonfire.Me.Fake.fake_user!()
      commenter = Bonfire.Me.Fake.fake_user!()

      # Configure threads to start new threads instead of raising when reply is not allowed
      Process.put(
        [:bonfire_social, Bonfire.Social.Threads, :start_new_thread_if_reply_not_allowed],
        true
      )

      # Create a post
      attrs = %{
        post_content: %{
          summary: "original post",
          html_body: "<p>original post content</p>"
        }
      }

      assert {:ok, post} =
               Posts.publish(current_user: author, post_attrs: attrs, boundary: "public")

      # Lock the post
      assert {:ok, _} =
               Bonfire.Boundaries.Blocks.block(post, :lock, current_user: author)
               |> debug("Locked post")

      refute Boundaries.can?(commenter, :reply, post)

      # Try to reply as another user - should create a new thread instead
      reply_attrs = %{
        post_content: %{
          summary: "reply",
          html_body: "<p>trying to reply</p>"
        },
        reply_to_id: post.id
      }

      # Commenter should still be able to read the post
      assert Boundaries.can?(commenter, :see, post)

      # Should succeed but create a new thread, not a reply
      assert {:ok, new_post} = Posts.publish(current_user: commenter, post_attrs: reply_attrs)

      # Verify it's a new thread, not a reply to the locked post
      refute new_post.replied.reply_to_id == post.id
      assert new_post.replied.thread_id == new_post.id, "Should start its own thread"
      assert is_nil(new_post.replied.reply_to_id), "Should not be a reply"

      # Unlock the post
      assert {:ok, _} =
               Bonfire.Boundaries.Blocks.unblock(post, :lock, current_user: author)
               |> debug("Unlocked post")

      # Try to reply - should now succeed as an actual reply
      reply_attrs = %{
        post_content: %{
          summary: "reply",
          html_body: "<p>successful reply</p>"
        },
        reply_to_id: post.id
      }

      assert {:ok, reply} = Posts.publish(current_user: commenter, post_attrs: reply_attrs)
      assert reply.replied.reply_to_id == post.id, "Should be an actual reply now"
    end

    test "locking doesn't affect existing replies, but prevents new replies to any sub-reply of the locked thread" do
      author = Bonfire.Me.Fake.fake_user!()
      commenter = Bonfire.Me.Fake.fake_user!()

      # Configure threads to start new threads instead of raising when reply is not allowed
      Process.put(
        [:bonfire_social, Bonfire.Social.Threads, :start_new_thread_if_reply_not_allowed],
        true
      )

      # Create a post
      attrs = %{
        post_content: %{
          summary: "post",
          html_body: "<p>post content</p>"
        }
      }

      assert {:ok, post} =
               Posts.publish(current_user: author, post_attrs: attrs, boundary: "public")

      # Add a reply before locking
      reply_attrs = %{
        post_content: %{
          summary: "early reply",
          html_body: "<p>replied before lock</p>"
        },
        reply_to_id: post.id
      }

      assert {:ok, reply} =
               Posts.publish(current_user: commenter, post_attrs: reply_attrs)
               |> debug("Created reply before locking")

      # Lock the post
      assert {:ok, _} = Bonfire.Boundaries.Blocks.block(post, :lock, current_user: author)

      # Existing reply should still be readable
      assert Boundaries.can?(commenter, :see, post)
      refute Boundaries.can?(commenter, :reply, post)

      # Try to reply to the existing reply - should create a new thread instead
      reply_to_reply_attrs = %{
        post_content: %{
          summary: "reply to reply",
          html_body: "<p>trying to reply to reply</p>"
        },
        reply_to_id: reply.id
      }

      # Should succeed but create a new thread, not a reply in the locked thread
      assert {:ok, new_post} =
               Posts.publish(current_user: commenter, post_attrs: reply_to_reply_attrs)

      # Verify it's a new thread, not part of the locked thread
      refute new_post.replied.reply_to_id == reply.id
      refute new_post.replied.thread_id == post.id
      assert new_post.replied.thread_id == new_post.id, "Should start its own thread"
      assert is_nil(new_post.replied.reply_to_id), "Should not be a reply"
    end
  end
end
