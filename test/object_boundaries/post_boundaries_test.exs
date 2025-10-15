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
end
