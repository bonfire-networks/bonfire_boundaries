defmodule Bonfire.Boundaries.Boundaries.InstanceWideSilenceActorFeedsPerUserTest do
  use Bonfire.Boundaries.DataCase
  @moduletag :backend

  import Tesla.Mock
  import Bonfire.Boundaries.Debug
  alias ActivityPub.Config
  alias Bonfire.Posts
  alias Bonfire.Data.ActivityPub.Peered
  alias Bonfire.Federate.ActivityPub.Simulate

  @my_name "alice"
  @other_name "bob"
  @attrs %{
    post_content: %{
      summary: "summary",
      name: "name",
      html_body: "<p>epic html message</p>"
    }
  }

  setup do
    # TODO: move this into fixtures
    mock(fn
      %{method: :get, url: @remote_actor} ->
        json(Simulate.actor_json(@remote_actor))
    end)
  end

  describe "" do
    test "shows in feeds a post with no instance-wide silencing" do
      alice = fake_user!(@my_name)
      bob = fake_user!(@other_name)

      assert {:ok, post} =
               Posts.publish(
                 current_user: bob,
                 post_attrs: @attrs,
                 boundary: "public"
               )

      assert Bonfire.Social.FeedActivities.feed_contains?(:local, post, current_user: alice)
      assert Bonfire.Social.FeedActivities.feed_contains?(:local, post)
    end

    test "does not show in any feeds a post from a instance-wide silenced user" do
      alice = fake_user!(@other_name)
      bob = fake_user!(@other_name)

      # view unlisted
      assert Bonfire.Boundaries.can?(alice, :read, bob)
      # discover
      assert Bonfire.Boundaries.can?(alice, :see, bob)

      Bonfire.Boundaries.Blocks.block(bob, :silence, :instance_wide)

      silence_list = Bonfire.Boundaries.Blocks.instance_wide_circles([:silence_them])

      # silence_list
      # |> Bonfire.Boundaries.Circles.list_by_ids()
      # |> repo().maybe_preload([:caretaker, encircle_subjects: [:profile]])
      # |> info("silenced details")

      assert Bonfire.Boundaries.Circles.is_encircled_by?(bob, silence_list)

      assert Bonfire.Boundaries.Blocks.is_blocked?(bob, :silence, :instance_wide)
      # view unlisted
      assert Bonfire.Boundaries.can?(:guest, :read, bob)
      # discover
      refute Bonfire.Boundaries.can?(:guest, :see, bob)

      # view unlisted
      assert Bonfire.Boundaries.can?(:local, :read, bob)
      # discover
      refute Bonfire.Boundaries.can?(:local, :see, bob)

      # view unlisted
      assert Bonfire.Boundaries.can?(alice, :read, bob)
      # discover
      refute Bonfire.Boundaries.can?(alice, :see, bob)

      local_circle = Bonfire.Boundaries.Blocks.instance_wide_circles([:local])

      # local_circle
      # |> Bonfire.Boundaries.Circles.list_by_ids()
      # |> repo().maybe_preload([:caretaker, encircle_subjects: [:profile]])
      # |> dump("local details")

      assert Bonfire.Boundaries.Circles.is_encircled_by?(alice, local_circle)
      assert Bonfire.Boundaries.Circles.is_encircled_by?(bob, local_circle)

      assert {:ok, post} =
               Posts.publish(
                 current_user: bob,
                 post_attrs: @attrs,
                 boundary: "public"
               )

      # debug_object_acls(post)
      refute Bonfire.Social.FeedActivities.feed_contains?(:local, post)
      # check that we do not show it to authenticated users either
      refute Bonfire.Social.FeedActivities.feed_contains?(:local, post, current_user: alice)
      # refute Bonfire.Social.FeedActivities.feed_contains?(:local, post, current_user: bob)
    end

    test "does not show in any feeds a post from an user that was instance-wide silenced later on" do
      alice = fake_user!(@other_name)
      bob = fake_user!(@other_name)
      # Bonfire.Boundaries.Blocks.instance_wide_circles([:silence_me])
      # |> Bonfire.Boundaries.Circles.list_by_ids()
      # |> repo().maybe_preload(caretaker: [:profile], encircles: [subject: [:profile]])
      # |> info("silenced details")
      assert {:ok, post} =
               Posts.publish(
                 current_user: bob,
                 post_attrs: @attrs,
                 boundary: "public"
               )

      # debug_object_acls(post)
      assert Bonfire.Social.FeedActivities.feed_contains?(:local, post)
      assert Bonfire.Social.FeedActivities.feed_contains?(:local, post, current_user: alice)

      Bonfire.Boundaries.Blocks.block(bob, :silence, :instance_wide)
      refute Bonfire.Social.FeedActivities.feed_contains?(:local, post)
      refute Bonfire.Social.FeedActivities.feed_contains?(:local, post, current_user: alice)

      # we show it once again
      Bonfire.Boundaries.Blocks.unblock(bob, :silence, :instance_wide)
      assert Bonfire.Social.FeedActivities.feed_contains?(:local, post)
      assert Bonfire.Social.FeedActivities.feed_contains?(:local, post, current_user: alice)
    end
  end
end
