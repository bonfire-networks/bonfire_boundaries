defmodule Bonfire.Boundaries.API.GraphQLTest do
  use Bonfire.Boundaries.DataCase, async: true

  alias Bonfire.API.GraphQL.Schema
  alias Bonfire.Boundaries.Circles

  import Bonfire.Me.Fake

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

  @post_options_query """
  query {
    boundaries(context: "post") {
      options {
        id
        label
        custom
      }
    }
  }
  """

  @add_to_circle_mutation """
  mutation($circleId: ID!, $subjectIds: [ID!]!) {
    add_to_circle(circle_id: $circleId, subject_ids: $subjectIds)
  }
  """

  @remove_from_circle_mutation """
  mutation($circleId: ID!, $subjectIds: [ID!]!) {
    remove_from_circle(circle_id: $circleId, subject_ids: $subjectIds)
  }
  """

  @create_circle_mutation """
  mutation($circle: CircleInput!) {
    create_circle(circle: $circle) {
      id
      name
      summary
    }
  }
  """

  @update_circle_mutation """
  mutation($id: ID!, $circle: CircleInput!) {
    update_circle(id: $id, circle: $circle) {
      id
      name
      summary
    }
  }
  """

  @delete_circle_mutation """
  mutation($id: ID!) {
    delete_circle(id: $id)
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

  test "post boundaries options returns built-in audiences without auth" do
    {:ok, result} = Absinthe.run(@post_options_query, Schema)

    refute result[:errors]

    options = get_in(result, [:data, "boundaries", "options"])
    assert is_list(options) and options != []

    ids = Enum.map(options, & &1["id"])
    assert "public" in ids
    assert "local" in ids
    assert "mentions" in ids
    assert Enum.all?(options, &(&1["custom"] == false))
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

  test "add_to_circle returns a GraphQL error for empty subject ids" do
    user = fake_user!()
    {:ok, circle} = Circles.create(user, %{named: %{name: "graphql circle"}})

    {:ok, result} =
      Absinthe.run(@add_to_circle_mutation, Schema,
        variables: %{"circleId" => circle.id, "subjectIds" => []},
        context: Schema.context(%{current_user: user})
      )

    assert result[:errors]
    assert get_in(result, [:data, "add_to_circle"]) == nil
  end

  test "remove_from_circle returns a GraphQL error for empty subject ids" do
    user = fake_user!()
    {:ok, circle} = Circles.create(user, %{named: %{name: "graphql circle"}})

    {:ok, result} =
      Absinthe.run(@remove_from_circle_mutation, Schema,
        variables: %{"circleId" => circle.id, "subjectIds" => []},
        context: Schema.context(%{current_user: user})
      )

    assert result[:errors]
    assert get_in(result, [:data, "remove_from_circle"]) == nil
  end

  test "circle CRUD mutations return useful success payloads" do
    user = fake_user!()

    {:ok, create_result} =
      Absinthe.run(@create_circle_mutation, Schema,
        variables: %{
          "circle" => %{
            "name" => "GraphQL friends",
            "summary" => "People I know from GraphQL"
          }
        },
        context: Schema.context(%{current_user: user})
      )

    refute create_result[:errors]
    created = get_in(create_result, [:data, "create_circle"])
    assert is_binary(created["id"])
    assert created["name"] == "GraphQL friends"
    assert created["summary"] == "People I know from GraphQL"

    {:ok, update_result} =
      Absinthe.run(@update_circle_mutation, Schema,
        variables: %{
          "id" => created["id"],
          "circle" => %{
            "name" => "GraphQL close friends",
            "summary" => "People I trust with test fixtures"
          }
        },
        context: Schema.context(%{current_user: user})
      )

    refute update_result[:errors]
    updated = get_in(update_result, [:data, "update_circle"])
    assert updated["id"] == created["id"]
    assert updated["name"] == "GraphQL close friends"
    assert updated["summary"] == "People I trust with test fixtures"

    {:ok, delete_result} =
      Absinthe.run(@delete_circle_mutation, Schema,
        variables: %{"id" => created["id"]},
        context: Schema.context(%{current_user: user})
      )

    refute delete_result[:errors]
    assert get_in(delete_result, [:data, "delete_circle"]) == true
  end

  test "circle update and delete return GraphQL errors for missing ids" do
    user = fake_user!()
    missing_id = "01JABCDEF0000000000000000G"

    {:ok, update_result} =
      Absinthe.run(@update_circle_mutation, Schema,
        variables: %{
          "id" => missing_id,
          "circle" => %{"name" => "Missing circle"}
        },
        context: Schema.context(%{current_user: user})
      )

    assert update_result[:errors]
    assert get_in(update_result, [:data, "update_circle"]) == nil

    {:ok, delete_result} =
      Absinthe.run(@delete_circle_mutation, Schema,
        variables: %{"id" => missing_id},
        context: Schema.context(%{current_user: user})
      )

    assert delete_result[:errors]
    assert get_in(delete_result, [:data, "delete_circle"]) == nil
  end
end
