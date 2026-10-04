defmodule Bonfire.Boundaries.Boundaries.InstanceWideHidePostFeedsPerUserTest do
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
    # the id is only resolved to know WHAT to hide, so a post a guest can't read (eg. a paid Ghost article, members-only) can still be hidden by id: an instance-wide block has no user to look it up as
    test "a post a guest can't read can still be hidden instance-wide by its id" do
      bob = Bonfire.Me.Fake.fake_user!(@other_name)

      assert {:ok, post} =
               Posts.publish(
                 current_user: bob,
                 post_attrs: @attrs,
                 boundary: "local"
               )

      refute Bonfire.Boundaries.can?(nil, :see, post.id),
             "control: a guest can't see this post, so looking it up as one finds nothing"

      assert {:ok, _} = Bonfire.Boundaries.Blocks.block(post.id, :hide, :instance_wide)
    end

    test "does not show in local feeds an instance-wide hidden post" do
      me = Bonfire.Me.Fake.fake_user!(@my_name)
      bob = Bonfire.Me.Fake.fake_user!(@other_name)

      assert {:ok, post} =
               Posts.publish(
                 current_user: bob,
                 post_attrs: @attrs,
                 boundary: "public"
               )

      assert Bonfire.Social.FeedLoader.feed_contains?(:local, post, me)

      Bonfire.Boundaries.Blocks.block(post, :hide, :instance_wide)

      refute Bonfire.Social.FeedLoader.feed_contains?(:local, post, me)
    end

    @tag :todo
    test "does not show in a thread an instance-wide hidden reply" do
    end
  end
end
