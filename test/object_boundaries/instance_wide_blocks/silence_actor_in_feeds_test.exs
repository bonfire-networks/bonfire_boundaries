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
      me = fake_user!(@my_name)
      bob = fake_user!(@other_name)

      assert {:ok, post} =
               Posts.publish(
                 current_user: bob,
                 post_attrs: @attrs,
                 boundary: "public"
               )

      assert Bonfire.Social.FeedActivities.feed_contains?(:local, post, current_user: me)
    end

    @tag :todo
    test "does not show in any feeds a post from a instance-wide silenced user" do
      bob = fake_user!(@other_name)

      Bonfire.Boundaries.Blocks.block(bob, :silence, :instance_wide)

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
      assert %{edges: []} = Bonfire.Social.FeedActivities.feed(:local)
      third_user = fake_user!()
      # check that we do not show it to authenticated users either
      assert %{edges: []} = Bonfire.Social.FeedActivities.feed(:local, current_user: third_user)
    end

    @tag :todo
    test "does not show in any feeds a post from an user that was instance-wide silenced later on" do
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
      feed_id = Bonfire.Social.Feeds.named_feed_id(:local)
      assert %{edges: [_]} = Bonfire.Social.FeedActivities.feed(:local)
      Bonfire.Boundaries.Blocks.block(bob, :silence, :instance_wide)
      assert %{edges: []} = Bonfire.Social.FeedActivities.feed(:local)
    end
  end
end
