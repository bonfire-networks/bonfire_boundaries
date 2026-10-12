defmodule Bonfire.Boundaries.Boundaries.BlockActorPerUserTest do
  @moduledoc """
  A per-user `:block` is a silence plus a ghost, and the two point in opposite directions. Silencing them stops ME discovering THEIR things (`silence_me` denies `:see` on their objects), but leaves `:read`, so I can still open their posts by direct link. Ghosting them stops THEM doing anything with MY things (`ghost_them` denies every verb on my objects), so they cannot open mine, even by direct link.
  """
  use Bonfire.Boundaries.DataCase
  @moduletag :backend

  alias Bonfire.Posts
  alias Bonfire.Boundaries.Blocks

  @attrs %{
    post_content: %{
      summary: "summary",
      name: "name",
      html_body: "<p>epic html message</p>"
    }
  }

  test "I can still read a post from someone I blocked by direct link, but not discover it" do
    me = Bonfire.Me.Fake.fake_user!()
    other_user = Bonfire.Me.Fake.fake_user!()

    assert {:ok, post} =
             Posts.publish(current_user: other_user, post_attrs: @attrs, boundary: "public")

    assert Bonfire.Boundaries.can?(me, :see, post),
           "the control: I can discover the post before blocking, so the refusal below is the block rather than the fixture"

    Blocks.block(other_user, :block, current_user: me)

    refute Bonfire.Boundaries.can?(me, :see, post)

    assert {:ok, read} = Posts.read(post.id, current_user: me)
    assert read.id == post.id
  end

  test "someone I blocked cannot read my post, even by direct link" do
    me = Bonfire.Me.Fake.fake_user!()
    other_user = Bonfire.Me.Fake.fake_user!()

    assert {:ok, post} = Posts.publish(current_user: me, post_attrs: @attrs, boundary: "public")

    assert {:ok, _} = Posts.read(post.id, current_user: other_user),
           "the control: they can read my post before the block, so the refusal below is the block rather than the fixture"

    Blocks.block(other_user, :block, current_user: me)

    assert {:error, :not_found} = Posts.read(post.id, current_user: other_user)

    third_user = Bonfire.Me.Fake.fake_user!()

    assert {:ok, _} = Posts.read(post.id, current_user: third_user),
           "and only for them: blocking is per-user, so everyone else can still read it"
  end
end
