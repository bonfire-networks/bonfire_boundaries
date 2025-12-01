if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled and
     Code.ensure_loaded?(Absinthe.Schema.Notation) do
  defmodule Bonfire.Boundaries.API.GraphQL do
    @moduledoc """
    GraphQL API for Circles (user groups for access control).

    Circles are used to organize users for boundaries/permissions and
    can also serve as lists (Mastodon-compatible).
    """
    use Absinthe.Schema.Notation
    use Absinthe.Relay.Schema.Notation, :modern
    use Bonfire.Common.Utils
    import Untangle

    alias Bonfire.API.GraphQL
    alias Bonfire.Boundaries.Circles
    alias Bonfire.Boundaries.Blocks

    # ==================
    # TYPE DEFINITIONS
    # ==================

    @desc "A circle (group of users) for organizing boundaries"
    object :circle do
      field(:id, non_null(:id))

      field :name, :string do
        resolve(&resolve_circle_name/3)
      end

      field :summary, :string do
        resolve(&resolve_circle_summary/3)
      end
    end

    @desc "A circle member (user in a circle)"
    object :circle_member do
      field(:id, non_null(:id))
      field(:subject_id, non_null(:id))

      field :subject, :user do
        resolve(Absinthe.Resolution.Helpers.dataloader(Needle.Pointer))
      end
    end

    @desc "Paginated circle members result"
    object :circle_members_page do
      field(:entries, list_of(:circle_member))
      field(:page_info, :circle_page_info)
    end

    @desc "Page info for circle pagination"
    object :circle_page_info do
      field(:has_next_page, :boolean)
      field(:has_previous_page, :boolean)
      field(:start_cursor, :string)
      field(:end_cursor, :string)
    end

    @desc "Input for creating/updating a circle"
    input_object :circle_input do
      field(:name, non_null(:string))
      field(:summary, :string)
    end

    @desc "Filter for listing circles"
    input_object :circle_filters do
      field(:id, :id)
      field(:exclude_stereotypes, :boolean)
      field(:exclude_built_ins, :boolean)
    end

    # ==================
    # QUERIES
    # ==================

    object :boundaries_queries do
      @desc "List circles owned by current user"
      field :my_circles, list_of(:circle) do
        arg(:filter, :circle_filters)
        arg(:limit, :integer)

        resolve(&list_my_circles/3)
      end

      @desc "Get a specific circle by ID"
      field :circle, :circle do
        arg(:id, non_null(:id))

        resolve(&get_circle/3)
      end

      @desc "List members of a circle"
      field :circle_members, :circle_members_page do
        arg(:circle_id, non_null(:id))
        arg(:limit, :integer)
        arg(:after, :string)
        arg(:before, :string)

        resolve(&list_circle_members/3)
      end

      @desc "List users blocked by the current user (both ghosted and silenced)"
      field :blocked_users, list_of(:user) do
        resolve(&list_blocked_users/3)
      end

      @desc "List users muted/silenced by the current user"
      field :muted_users, list_of(:user) do
        resolve(&list_muted_users/3)
      end
    end

    # ==================
    # MUTATIONS
    # ==================

    object :boundaries_mutations do
      @desc "Create a new circle"
      field :create_circle, :circle do
        arg(:circle, non_null(:circle_input))

        resolve(&create_circle/2)
      end

      @desc "Update a circle"
      field :update_circle, :circle do
        arg(:id, non_null(:id))
        arg(:circle, non_null(:circle_input))

        resolve(&update_circle/2)
      end

      @desc "Delete a circle"
      field :delete_circle, :boolean do
        arg(:id, non_null(:id))

        resolve(&delete_circle/2)
      end

      @desc "Add accounts to a circle"
      field :add_to_circle, :boolean do
        arg(:circle_id, non_null(:id))
        arg(:subject_ids, non_null(list_of(non_null(:id))))

        resolve(&add_to_circle/2)
      end

      @desc "Remove accounts from a circle"
      field :remove_from_circle, :boolean do
        arg(:circle_id, non_null(:id))
        arg(:subject_ids, non_null(list_of(non_null(:id))))

        resolve(&remove_from_circle/2)
      end

      @desc "Block a user (ghost + silence them)"
      field :block_user, :user do
        arg(:id, non_null(:id))

        resolve(&block_user/2)
      end

      @desc "Unblock a user"
      field :unblock_user, :user do
        arg(:id, non_null(:id))

        resolve(&unblock_user/2)
      end

      @desc "Mute/silence a user (hide their content from you)"
      field :mute_user, :user do
        arg(:id, non_null(:id))

        resolve(&mute_user/2)
      end

      @desc "Unmute/unsilence a user"
      field :unmute_user, :user do
        arg(:id, non_null(:id))

        resolve(&unmute_user/2)
      end
    end

    # ==================
    # RESOLVER FUNCTIONS
    # ==================

    defp resolve_circle_name(%{named: %{name: name}}, _, _) when is_binary(name), do: {:ok, name}
    defp resolve_circle_name(%{name: name}, _, _) when is_binary(name), do: {:ok, name}
    defp resolve_circle_name(_, _, _), do: {:ok, nil}

    defp resolve_circle_summary(%{extra_info: %{summary: summary}}, _, _) when is_binary(summary),
      do: {:ok, summary}

    defp resolve_circle_summary(%{summary: summary}, _, _) when is_binary(summary),
      do: {:ok, summary}

    defp resolve_circle_summary(_, _, _), do: {:ok, nil}

    defp list_my_circles(_parent, args, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info) do
        filter = args[:filter] || %{}

        opts = [
          exclude_stereotypes: Map.get(filter, :exclude_stereotypes, false),
          exclude_built_ins: Map.get(filter, :exclude_built_ins, false),
          preload: [:named, :extra_info]
        ]

        circles = Circles.list_my(user, opts)
        {:ok, circles}
      end
    end

    defp get_circle(_parent, %{id: id}, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info),
           {:ok, circle} <- Circles.get_for_caretaker(id, user, preload: [:named, :extra_info]) do
        {:ok, circle}
      end
    end

    defp list_circle_members(_parent, %{circle_id: circle_id} = args, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info),
           {:ok, circle} <- Circles.get_for_caretaker(circle_id, user) do
        opts =
          [
            limit: args[:limit] || 40,
            after: args[:after],
            before: args[:before]
          ]
          |> Enum.reject(fn {_, v} -> is_nil(v) end)

        result = Circles.list_members(circle, opts)
        {entries, page_info} = extract_entries_and_page_info(result)

        {:ok,
         %{
           entries: entries,
           page_info: page_info
         }}
      end
    end

    # Handle Paginator.Page struct (has `edges` and `page_info`)
    defp extract_entries_and_page_info(%{edges: edges, page_info: page_info}) do
      page_info_map = %{
        has_next_page: page_info.end_cursor != nil,
        has_previous_page: page_info.start_cursor != nil,
        start_cursor: page_info.start_cursor,
        end_cursor: page_info.end_cursor
      }

      {edges, page_info_map}
    end

    defp extract_entries_and_page_info(%{entries: entries, metadata: metadata}) do
      page_info = %{
        has_next_page: Map.get(metadata, :after) != nil,
        has_previous_page: Map.get(metadata, :before) != nil,
        start_cursor: encode_cursor(List.first(entries)),
        end_cursor: encode_cursor(List.last(entries))
      }

      {entries, page_info}
    end

    defp extract_entries_and_page_info(%{entries: entries}) do
      {entries, %{has_next_page: false, has_previous_page: false}}
    end

    defp extract_entries_and_page_info(list) when is_list(list) do
      {list, %{has_next_page: false, has_previous_page: false}}
    end

    defp extract_entries_and_page_info(_), do: {[], %{}}

    defp encode_cursor(nil), do: nil

    defp encode_cursor(%{id: id}) when is_binary(id) do
      %{{:encircle, :id} => id}
      |> :erlang.term_to_binary()
      |> Base.url_encode64()
    end

    defp encode_cursor(_), do: nil

    defp create_circle(%{circle: %{name: name} = circle_input}, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info) do
        attrs = %{
          named: %{name: name},
          extra_info: %{summary: Map.get(circle_input, :summary)}
        }

        case Circles.create(user, attrs) do
          {:ok, circle} ->
            # Preload named for response
            circle = Bonfire.Common.Repo.maybe_preload(circle, [:named, :extra_info])
            {:ok, circle}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end

    defp update_circle(%{id: id, circle: %{name: name} = circle_input}, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info) do
        attrs = %{
          named: %{name: name},
          extra_info: %{summary: Map.get(circle_input, :summary)}
        }

        case Circles.edit(id, user, attrs) do
          {:ok, circle} ->
            circle = Bonfire.Common.Repo.maybe_preload(circle, [:named, :extra_info])
            {:ok, circle}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end

    defp delete_circle(%{id: id}, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info),
           {:ok, _} <- Circles.delete(id, current_user: user) do
        {:ok, true}
      end
    end

    defp add_to_circle(%{circle_id: circle_id, subject_ids: subject_ids}, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info),
           {:ok, circle} <- Circles.get_for_caretaker(circle_id, user) do
        case Circles.add_to_circles(subject_ids, circle) do
          {:ok, _} -> {:ok, true}
          # add_to_circles may not return a tuple
          _ -> {:ok, true}
        end
      end
    end

    defp remove_from_circle(%{circle_id: circle_id, subject_ids: subject_ids}, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info),
           {:ok, circle} <- Circles.get_for_caretaker(circle_id, user) do
        case Circles.remove_from_circles(subject_ids, circle) do
          {:ok, _} -> {:ok, true}
          # remove_from_circles may not return a tuple
          _ -> {:ok, true}
        end
      end
    end

    # ==================
    # BLOCK/MUTE RESOLVERS
    # ==================

    defp list_blocked_users(_parent, _args, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info) do
        # Get users who are BOTH ghosted AND silenced (full block = Mastodon semantics)
        ghost_circles = Blocks.list(:ghost, current_user: user)
        silence_circles = Blocks.list(:silence, current_user: user)

        ghosted_ids = extract_user_ids_from_circles(ghost_circles)
        silenced_ids = extract_user_ids_from_circles(silence_circles)

        # Intersection: users who are both ghosted AND silenced
        blocked_ids =
          MapSet.intersection(MapSet.new(ghosted_ids), MapSet.new(silenced_ids))
          |> MapSet.to_list()

        users = Bonfire.Me.Users.by_ids(blocked_ids)
        {:ok, users}
      end
    end

    defp list_muted_users(_parent, _args, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info) do
        circles = Blocks.list(:silence, current_user: user)
        user_ids = extract_user_ids_from_circles(circles)
        users = Bonfire.Me.Users.by_ids(user_ids)
        {:ok, users}
      end
    end

    defp block_user(%{id: id}, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info) do
        ghost_result = Blocks.block(id, :ghost, current_user: user)
        silence_result = Blocks.block(id, :silence, current_user: user)

        case {ghost_result, silence_result} do
          {{:ok, _}, {:ok, _}} ->
            Bonfire.Me.Users.by_id(id)

          {_, {:ok, _}} ->
            Bonfire.Me.Users.by_id(id)

          {{:ok, _}, _} ->
            Bonfire.Me.Users.by_id(id)

          _ ->
            {:error, "Could not block user"}
        end
      end
    end

    defp unblock_user(%{id: id}, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info) do
        ghost_result = Blocks.unblock(id, :ghost, current_user: user)
        silence_result = Blocks.unblock(id, :silence, current_user: user)

        case {ghost_result, silence_result} do
          {{:ok, _}, {:ok, _}} ->
            Bonfire.Me.Users.by_id(id)

          {_, {:ok, _}} ->
            Bonfire.Me.Users.by_id(id)

          {{:ok, _}, _} ->
            Bonfire.Me.Users.by_id(id)

          _ ->
            {:error, "Could not unblock user"}
        end
      end
    end

    defp mute_user(%{id: id}, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info),
           # :silence block_type = mute only
           {:ok, _} <- Blocks.block(id, :silence, current_user: user) do
        # Return the muted user
        Bonfire.Me.Users.by_id(id)
      end
    end

    defp unmute_user(%{id: id}, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info),
           # :silence block_type = unmute only
           {:ok, _} <- Blocks.unblock(id, :silence, current_user: user) do
        # Return the unmuted user
        Bonfire.Me.Users.by_id(id)
      end
    end

    # Helper to extract users from block circles
    defp extract_users_from_circles(circles) when is_list(circles) do
      circles
      |> Enum.flat_map(fn circle ->
        case circle do
          %{encircles: encircles} when is_list(encircles) ->
            Enum.map(encircles, &e(&1, :subject, nil))

          _ ->
            []
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&Bonfire.Common.Types.uid/1)
    end

    defp extract_users_from_circles(_), do: []

    # Helper to extract user IDs from block circles
    defp extract_user_ids_from_circles(circles) do
      circles
      |> extract_users_from_circles()
      |> Enum.map(&Bonfire.Common.Types.uid/1)
      |> Enum.reject(&is_nil/1)
    end
  end
end
