defmodule Bonfire.Boundaries.GroupBatchMetadataTest do
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries.{Circles, Controlleds, Presets}
  alias Bonfire.Me.Fake

  test "member counts distinguish an empty circle from a missing circle" do
    populated_owner = Fake.fake_user!()
    empty_owner = Fake.fake_user!()
    missing_owner = Fake.fake_user!()
    assert {:ok, populated} = Circles.create_stereotype_circle(populated_owner, :group_members)
    assert {:ok, empty} = Circles.create_stereotype_circle(empty_owner, :group_members)
    Circles.add_to_circles(populated_owner, populated)
    Circles.add_to_circles(empty_owner, populated)
    assert Circles.count_members(populated) == 2

    counts = Circles.count_members_of_objects([populated_owner, empty_owner, missing_owner], :group_members)
    require Logger
    Logger.info("Batch member counts: #{inspect(counts)}; empty circle count: #{Circles.count_members(empty)}")

    assert counts == %{populated_owner.id => Circles.count_members(populated), empty_owner.id => 0}
    assert counts == Circles.count_members_of_objects([populated_owner.id, empty_owner.id, missing_owner.id], :group_members)
  end

  test "batch ACLs and listing dimensions agree with individual reads across presets" do
    creator = Fake.fake_user!()
    groups =
      for dims <- [
        %{membership: "local:members", visibility: "nonfederated", participation: "group_members"},
        %{membership: "on_request", visibility: "local:discoverable", participation: "group_members"},
        %{membership: "invite_only", visibility: "nonfederated", participation: "moderators"}
      ] do
        Bonfire.Classify.Simulate.fake_group!(creator, Map.put(dims, :name, Faker.Lorem.word()))
      end

    acls = Controlleds.list_acl_ids_on_objects(groups)
    dimensions = Presets.group_listing_dimension_slugs(groups)

    for group <- groups do
      expected_acls =
        Controlleds.list_acls_on_object(group)
        |> Enum.map(& &1.acl_id)
        |> MapSet.new()

      assert acls[group.id] == expected_acls
      assert Map.take(dimensions[group.id], [:membership, :visibility]) ==
               Map.take(Presets.group_dimension_slugs(group), [:membership, :visibility])
      assert dimensions[group.id].participation == nil
    end

    assert acls == Controlleds.list_acl_ids_on_objects(Enum.map(groups, & &1.id))
  end

  test "empty batches return empty maps" do
    assert Circles.count_members_of_objects([], :group_members) == %{}
    assert Controlleds.list_acl_ids_on_objects([]) == %{}
    assert Presets.group_listing_dimension_slugs([]) == %{}
  end
end
