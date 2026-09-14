defmodule Bonfire.Boundaries.RequestVerbTest do
  @moduledoc """
  Asking is available by default, withheld where the group means no, and denied in two distinguishable degrees.

  `:request` is one verb covering every kind of asking, so it has a single home: the MEMBERSHIP dimension grants it, by every value of it that means yes. It is granted by an ACL that says so rather than riding along with `:read`, because otherwise a group could not withhold it without also taking away reading. An announcement channel is the case that needs withholding, and `announcement_channel` is `invite_only` membership with `moderators` participation, so neither dimension grants it and the ask is never offered.

  The negative `cannot_*` ladder keeps its own floor. Each rung denies everything except the rung below, and `:request` sits beneath all of them, so however denied someone is they may still ask to follow or join. Taking that away is a separate decision with its own role, so that choosing it is deliberate rather than a side effect of picking a rung.
  """
  use Bonfire.Boundaries.DataCase, async: false
  use Bonfire.Common.Utils
  @moduletag :backend

  alias Bonfire.Boundaries.Controlleds
  alias Bonfire.Classify.Simulate
  alias Bonfire.Me.Fake

  setup do
    # nothing here federates; applying boundaries otherwise spawns federation tasks with no DB ownership in tests
    Process.put(:federating, false)

    :ok
  end

  defp group_with(creator, dims) do
    group = Simulate.fake_group!(creator, %{type: :group})

    :ok =
      Bonfire.Classify.Boundaries.apply(
        group,
        creator,
        Map.merge(
          %{
            membership: "on_request",
            visibility: "global",
            participation: "anyone",
            default_content_visibility: "public"
          },
          dims
        )
      )

    group
  end

  describe "the negative ladder's floor" do
    test "someone denied participation may still ask" do
      creator = Fake.fake_user!()
      silenced = Fake.fake_user!()

      group = group_with(creator, %{})

      assert Bonfire.Boundaries.can?(silenced, :request, group) == true,
             "the group grants asking, which is the state this test then takes away from"

      Controlleds.grant_role(uid(silenced), group, :cannot_participate, current_user: creator)

      refute Bonfire.Boundaries.can?(silenced, :reply, group) == true,
             "`cannot_participate` is the silencing, so it has to actually silence"

      assert Bonfire.Boundaries.can?(silenced, :request, group) == true,
             "denying someone the ask as well is a separate decision, so picking this rung must not make it for them"
    end

    test "someone denied participation and asking may not ask" do
      creator = Fake.fake_user!()
      silenced = Fake.fake_user!()

      group = group_with(creator, %{})

      Controlleds.grant_role(uid(silenced), group, :cannot_participate_or_request,
        current_user: creator
      )

      refute Bonfire.Boundaries.can?(silenced, :reply, group) == true

      refute Bonfire.Boundaries.can?(silenced, :request, group) == true,
             "this is the rung a moderator picks when the asking itself is the problem"
    end
  end

  # Asking is granted by the MEMBERSHIP dimension, by every value of it that means yes. The pair below has to be read together: on its own, a refused `:request` is indistinguishable from a group whose boundaries never got applied.
  describe "asking on the positive side" do
    test "a group anyone may join still lets them ask" do
      creator = Fake.fake_user!()
      member = Fake.fake_user!()

      group = group_with(creator, %{membership: "open", participation: "anyone"})

      assert Bonfire.Boundaries.can?(member, :request, group) == true,
             "asking is available by default wherever membership says yes, so `open` grants it like the rest"

      assert Bonfire.Boundaries.can?(member, :tag, group) == true,
             "the control: the fixture really does apply the dimensions, so the refusals below mean something"
    end

    test "an announcement channel offers nobody the ask, with no negative role in play" do
      creator = Fake.fake_user!()
      member = Fake.fake_user!()

      # what `announcement_channel` actually declares (`bonfire_classify/lib/runtime_config.ex:118`): people FOLLOW it rather than joining, and only moderators post
      group = group_with(creator, %{membership: "invite_only", participation: "moderators"})

      refute Bonfire.Boundaries.can?(member, :tag, group) == true,
             "posting into a moderators-only channel is what it withholds"

      refute Bonfire.Boundaries.can?(member, :request, group) == true,
             "neither dimension grants asking here, so the answer is no by omission rather than by a rule anyone had to write"
    end
  end
end
