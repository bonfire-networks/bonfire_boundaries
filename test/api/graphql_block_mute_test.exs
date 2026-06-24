if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.Boundaries.API.GraphQLBlockMuteTest do
    use Bonfire.Boundaries.DataCase, async: false

    import Bonfire.Me.Fake

    alias Bonfire.API.GraphQL.Schema

    @moduletag :graphql

    @block_mutation """
    mutation($id: ID!) {
      block_user(id: $id) {
        id
      }
    }
    """

    @unblock_mutation """
    mutation($id: ID!) {
      unblock_user(id: $id) {
        id
      }
    }
    """

    @mute_mutation """
    mutation($id: ID!) {
      mute_user(id: $id) {
        id
      }
    }
    """

    @unmute_mutation """
    mutation($id: ID!) {
      unmute_user(id: $id) {
        id
      }
    }
    """

    @lists_query """
    query {
      blocked_users {
        id
      }
      muted_users {
        id
      }
    }
    """

    setup do
      me = fake_user!()
      target = fake_user!()

      {:ok, me: me, target: target}
    end

    test "blockUser returns the target only after both ghost and silence state are present", %{
      me: me,
      target: target
    } do
      {:ok, result} =
        Absinthe.run(@block_mutation, Schema,
          variables: %{"id" => target.id},
          context: Schema.context(%{current_user: me})
        )

      refute result[:errors]
      assert get_in(result, [:data, "block_user", "id"]) == target.id

      {:ok, lists} =
        Absinthe.run(@lists_query, Schema, context: Schema.context(%{current_user: me}))

      refute lists[:errors]
      assert target.id in ids_at(lists, "blocked_users")
      assert target.id in ids_at(lists, "muted_users")
    end

    test "unblockUser clears both block and mute list membership", %{me: me, target: target} do
      {:ok, _} =
        Absinthe.run(@block_mutation, Schema,
          variables: %{"id" => target.id},
          context: Schema.context(%{current_user: me})
        )

      {:ok, result} =
        Absinthe.run(@unblock_mutation, Schema,
          variables: %{"id" => target.id},
          context: Schema.context(%{current_user: me})
        )

      refute result[:errors]
      assert get_in(result, [:data, "unblock_user", "id"]) == target.id

      {:ok, lists} =
        Absinthe.run(@lists_query, Schema, context: Schema.context(%{current_user: me}))

      refute lists[:errors]
      refute target.id in ids_at(lists, "blocked_users")
      refute target.id in ids_at(lists, "muted_users")
    end

    test "muteUser and unmuteUser update only the muted list", %{me: me, target: target} do
      {:ok, muted} =
        Absinthe.run(@mute_mutation, Schema,
          variables: %{"id" => target.id},
          context: Schema.context(%{current_user: me})
        )

      refute muted[:errors]
      assert get_in(muted, [:data, "mute_user", "id"]) == target.id

      {:ok, lists} =
        Absinthe.run(@lists_query, Schema, context: Schema.context(%{current_user: me}))

      refute lists[:errors]
      refute target.id in ids_at(lists, "blocked_users")
      assert target.id in ids_at(lists, "muted_users")

      {:ok, unmuted} =
        Absinthe.run(@unmute_mutation, Schema,
          variables: %{"id" => target.id},
          context: Schema.context(%{current_user: me})
        )

      refute unmuted[:errors]
      assert get_in(unmuted, [:data, "unmute_user", "id"]) == target.id
    end

    defp ids_at(result, key) do
      result
      |> get_in([:data, key])
      |> List.wrap()
      |> Enum.map(& &1["id"])
    end
  end
end
