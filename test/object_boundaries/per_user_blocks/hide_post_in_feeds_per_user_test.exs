defmodule Bonfire.Boundaries.Boundaries.HidePostFeedsPerUserTest do
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
    test "does not show in local feed a per-user hidden post" do
      me = Bonfire.Me.Fake.fake_user!(@my_name)
      other_user = Bonfire.Me.Fake.fake_user!(@other_name)

      assert {:ok, post} =
               Posts.publish(
                 current_user: other_user,
                 post_attrs: @attrs,
                 boundary: "public"
               )

      assert Bonfire.Social.FeedLoader.feed_contains?(:local, post, me)

      Bonfire.Boundaries.Blocks.block(post, :hide, current_user: me)

      refute Bonfire.Social.FeedLoader.feed_contains?(:local, post, me)
    end

    @tag :todo
    test "does not show in a thread a per-user hidden reply" do
    end
  end
end
