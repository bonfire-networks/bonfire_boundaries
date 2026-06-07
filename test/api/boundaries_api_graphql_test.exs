defmodule Bonfire.Boundaries.API.GraphQLTest do
  use Bonfire.Boundaries.DataCase, async: true

  alias Bonfire.API.GraphQL.Schema

  @moduletag :graphql

  @query """
  query($ctx: String) {
    boundaries(context: $ctx) {
      context
      presets { id label description icon dimensions { key value } overrides_locked }
      overrides { key label help }
      dimensions { key label options { value label icon description disabled } }
    }
  }
  """

  test "BoundaryLabelledOption type has value, label, icon, description fields" do
    {:ok, result} =
      Absinthe.run(~S|{ __type(name: "BoundaryLabelledOption") { fields { name } } }|, Schema)

    names = get_in(result, [:data, "__type", "fields"]) |> Enum.map(& &1["name"])
    assert "value" in names
    assert "label" in names
    assert "icon" in names
    assert "description" in names
    refute result[:errors]
  end

  test "returns group presets from runtime config" do
    {:ok, result} = Absinthe.run(@query, Schema, variables: %{"ctx" => "group"})
    ids = get_in(result, [:data, "boundaries", "presets"]) |> Enum.map(& &1["id"])
    assert "public_local_community" in ids
    assert "private_club" in ids
    assert "announcement_channel" in ids
  end

  test "each preset includes all 4 dimension keys" do
    {:ok, result} = Absinthe.run(@query, Schema, variables: %{"ctx" => "group"})
    presets = get_in(result, [:data, "boundaries", "presets"])

    for preset <- presets do
      dim_keys = Enum.map(preset["dimensions"], & &1["key"])
      assert "membership" in dim_keys
      assert "visibility" in dim_keys
      assert "participation" in dim_keys
      assert "default_content_visibility" in dim_keys
    end
  end

  test "presets include overrides_locked list" do
    {:ok, result} = Absinthe.run(@query, Schema, variables: %{"ctx" => "group"})
    presets = get_in(result, [:data, "boundaries", "presets"])
    private_club = Enum.find(presets, &(&1["id"] == "private_club"))
    assert is_list(private_club["overrides_locked"])
    assert "federate" in private_club["overrides_locked"]
  end

  test "returns layer2 override toggles" do
    {:ok, result} = Absinthe.run(@query, Schema, variables: %{"ctx" => "group"})
    keys = get_in(result, [:data, "boundaries", "overrides"]) |> Enum.map(& &1["key"])
    assert "discoverable" in keys
    assert "approval_required" in keys
    assert "anyone_posts" in keys
    assert "federate" in keys
  end

  test "membership dimension has expected options" do
    {:ok, result} = Absinthe.run(@query, Schema, variables: %{"ctx" => "group"})
    dims = get_in(result, [:data, "boundaries", "dimensions"])
    membership = Enum.find(dims, &(&1["key"] == "membership"))
    assert membership
    values = Enum.map(membership["options"], & &1["value"])
    assert "open" in values
    assert "on_request" in values
    assert "invite_only" in values
  end

  test "disabled on dimension option is a string or nil, not boolean" do
    {:ok, result} = Absinthe.run(@query, Schema, variables: %{"ctx" => "group"})
    dims = get_in(result, [:data, "boundaries", "dimensions"])

    for dim <- dims, opt <- dim["options"] do
      assert opt["disabled"] == nil or is_binary(opt["disabled"]),
             "disabled should be string or nil, got: #{inspect(opt["disabled"])} for #{opt["value"]}"
    end
  end

  test "BoundaryPreset type exists in schema" do
    {:ok, result} =
      Absinthe.run(~S|{ __type(name: "BoundaryPreset") { fields { name } } }|, Schema)

    names = get_in(result, [:data, "__type", "fields"]) |> Enum.map(& &1["name"])
    assert "id" in names
    assert "label" in names
    assert "dimensions" in names
    assert "overridesLocked" in names
    refute result[:errors]
  end
end
