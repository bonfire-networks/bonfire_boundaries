if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.Boundaries.API.GraphQLMasto.Adapter do
    @moduledoc "Mutes/Blocks API endpoints for Mastodon-compatible client apps, powered by the GraphQL API"

    use Bonfire.Common.Utils
    use Arrows
    import Untangle

    use AbsintheClient,
      schema: Bonfire.API.GraphQL.Schema,
      action: [mode: :internal]

    alias Bonfire.API.GraphQL.RestAdapter

    # Override to add Dataloader context (AbsintheClient doesn't call schema's context/1)
    def absinthe_pipeline(schema, opts) do
      # Get existing context or empty map
      context = Keyword.get(opts, :context, %{})

      # Add Dataloader if not already present
      context_with_loader =
        if Map.has_key?(context, :loader) do
          context
        else
          # Call the schema's context function to get Dataloader
          schema.context(context)
        end

      opts_with_loader = Keyword.put(opts, :context, context_with_loader)
      AbsintheClient.default_pipeline(schema, opts_with_loader)
    end

    alias Bonfire.Boundaries.Blocks
    alias Bonfire.API.MastoCompat.{Fragments, Mappers, Schemas, PaginationHelpers}
    alias Bonfire.Social.Graph.Follows

    # User profile fragment inlined for compile-order independence
    @user_profile Fragments.user_profile()

    # Helper to list restricted accounts (mutes/blocks) via GraphQL
    defp list_restricted_accounts(conn, query_name, data_key) do
      case graphql(conn, query_name, %{}) do
        %{data: data} when is_map(data) ->
          current_user = conn.assigns[:current_user]
          users = Map.get(data, data_key, [])

          accounts =
            users
            |> Enum.map(
              &Mappers.Account.from_user(&1,
                current_user: current_user,
                skip_expensive_stats: true
              )
            )
            |> Enum.reject(&is_nil/1)

          RestAdapter.json(conn, accounts)

        %{errors: errors} ->
          RestAdapter.error_fn({:error, errors}, conn)

        _ ->
          RestAdapter.json(conn, [])
      end
    end

    @graphql "query {
      muted_users {
        #{@user_profile}
      }
    }"
    @doc "List muted accounts for current user"
    def mutes(_params, conn), do: list_restricted_accounts(conn, :mutes, :muted_users)

    @graphql "query {
      blocked_users {
        #{@user_profile}
      }
    }"
    @doc "List blocked accounts for current user"
    def blocks(_params, conn), do: list_restricted_accounts(conn, :blocks, :blocked_users)

    @doc "Mute an account"
    def mute_account(%{"id" => id}, conn), do: handle_block_action(conn, id, :mute)

    @doc "Unmute an account"
    def unmute_account(%{"id" => id}, conn), do: handle_block_action(conn, id, :unmute)

    @doc "Block an account"
    def block_account(%{"id" => id}, conn), do: handle_block_action(conn, id, :block)

    @doc "Unblock an account"
    def unblock_account(%{"id" => id}, conn), do: handle_block_action(conn, id, :unblock)

    # GraphQL mutations for block/mute actions (must be public for @graphql to work)
    @graphql "mutation ($id: ID!) {
      block_user(id: $id) {
        id
      }
    }"
    def do_block_user(conn, id) do
      graphql(conn, :do_block_user, %{"id" => id})
    end

    @graphql "mutation ($id: ID!) {
      unblock_user(id: $id) {
        id
      }
    }"
    def do_unblock_user(conn, id) do
      graphql(conn, :do_unblock_user, %{"id" => id})
    end

    @graphql "mutation ($id: ID!) {
      mute_user(id: $id) {
        id
      }
    }"
    def do_mute_user(conn, id) do
      graphql(conn, :do_mute_user, %{"id" => id})
    end

    @graphql "mutation ($id: ID!) {
      unmute_user(id: $id) {
        id
      }
    }"
    def do_unmute_user(conn, id) do
      graphql(conn, :do_unmute_user, %{"id" => id})
    end

    defp handle_block_action(conn, target_id, action) do
      current_user = conn.assigns[:current_user]

      if is_nil(current_user) do
        RestAdapter.error_fn({:error, :unauthorized}, conn)
      else
        result =
          case action do
            # Mastodon "mute" = Bonfire "silence" (user can't reach you)
            :mute -> do_mute_user(conn, target_id)
            :unmute -> do_unmute_user(conn, target_id)
            # Mastodon "block" = Bonfire ghost + silence (full isolation)
            :block -> do_block_user(conn, target_id)
            :unblock -> do_unblock_user(conn, target_id)
          end

        case result do
          %{data: data} when is_map(data) ->
            relationship = build_relationship(current_user, target_id)
            RestAdapter.json(conn, relationship)

          %{errors: errors} ->
            RestAdapter.error_fn({:error, errors}, conn)

          _ ->
            RestAdapter.error_fn({:error, :unexpected_response}, conn)
        end
      end
    end

    @doc """
    Build a Mastodon Relationship object by querying actual state.
    This is used by both block/mute endpoints and the relationships endpoint.
    """
    def build_relationship(current_user, target_id) do
      blocking = Blocks.is_blocked?(target_id, :ghost, current_user: current_user)
      muting = Blocks.is_blocked?(target_id, :silence, current_user: current_user)
      following = Follows.following?(current_user, target_id)
      followed_by = Follows.following?(target_id, current_user)

      # Check for pending follow request (only if not already following)
      # "requested" = Are you waiting for this user to accept your follow request?
      requested = if not following, do: Follows.requested?(current_user, target_id), else: false

      Schemas.Relationship.new(%{
        "id" => to_string(target_id),
        "following" => following,
        "followed_by" => followed_by,
        "blocking" => blocking,
        "muting" => muting,
        "muting_notifications" => muting,
        "requested" => requested
      })
    end

    @circle "
    id
    name
    summary
    "

    @circle_member "
    id
    subject_id: subjectId
    subject {
      ... on User {
        #{@user_profile}
      }
    }
    "

    @doc """
    Get all lists owned by the authenticated user.

    Returns an array of Mastodon List objects. System circles (built-in and
    stereotypes like followers/blocked) are filtered out, only user-created
    circles are returned.

    Endpoint: GET /api/v1/lists
    """
    @graphql "query ($filter: CircleFilters) {
      my_circles(filter: $filter) {
        #{@circle}
      }
    }"
    def lists(_params, conn) do
      filter = %{
        "exclude_stereotypes" => true,
        "exclude_built_ins" => true
      }

      case graphql(conn, :lists, %{"filter" => filter}) do
        %{data: %{my_circles: circles}} when is_list(circles) ->
          lists =
            circles
            |> Enum.map(&Mappers.List.from_circle/1)
            |> Enum.reject(&is_nil/1)

          RestAdapter.json(conn, lists)

        %{errors: errors} ->
          RestAdapter.error_fn({:error, errors}, conn)

        _ ->
          RestAdapter.error_fn({:error, :unexpected_response}, conn)
      end
    end

    @doc """
    Create a new list.

    Endpoint: POST /api/v1/lists
    """
    @graphql "mutation ($circle: CircleInput!) {
      create_circle(circle: $circle) {
        #{@circle}
      }
    }"
    def create_list(params, conn) do
      with_valid_title(params, conn, fn title ->
        case graphql(conn, :create_list, %{"circle" => %{"name" => title}}) do
          %{data: %{create_circle: circle}} when not is_nil(circle) ->
            list = Mappers.List.from_circle(circle)
            RestAdapter.json(conn, list)

          %{errors: errors} ->
            RestAdapter.error_fn({:error, errors}, conn)

          _ ->
            RestAdapter.error_fn({:error, :unexpected_response}, conn)
        end
      end)
    end

    @doc """
    Get a specific list by ID.

    Endpoint: GET /api/v1/lists/:id
    """
    @graphql "query ($id: ID!) {
      circle(id: $id) {
        #{@circle}
      }
    }"
    def show_list(id, _params, conn) do
      case graphql(conn, :show_list, %{"id" => id}) do
        %{data: %{circle: circle}} when not is_nil(circle) ->
          list = Mappers.List.from_circle(circle)
          RestAdapter.json(conn, list)

        %{data: %{circle: nil}} ->
          RestAdapter.error_fn({:error, :not_found}, conn)

        %{errors: errors} ->
          RestAdapter.error_fn({:error, errors}, conn)

        _ ->
          RestAdapter.error_fn({:error, :not_found}, conn)
      end
    end

    @doc """
    Update a list (change title).

    Endpoint: PUT /api/v1/lists/:id
    """
    @graphql "mutation ($id: ID!, $circle: CircleInput!) {
      update_circle(id: $id, circle: $circle) {
        #{@circle}
      }
    }"
    def update_list(id, params, conn) do
      with_valid_title(params, conn, fn title ->
        case graphql(conn, :update_list, %{"id" => id, "circle" => %{"name" => title}}) do
          %{data: %{update_circle: circle}} when not is_nil(circle) ->
            list = Mappers.List.from_circle(circle)
            RestAdapter.json(conn, list)

          %{errors: errors} ->
            RestAdapter.error_fn({:error, errors}, conn)

          _ ->
            RestAdapter.error_fn({:error, :unexpected_response}, conn)
        end
      end)
    end

    @doc """
    Delete a list.

    Endpoint: DELETE /api/v1/lists/:id
    """
    @graphql "mutation ($id: ID!) {
      delete_circle(id: $id)
    }"
    def delete_list(id, _params, conn) do
      case graphql(conn, :delete_list, %{"id" => id}) do
        %{data: %{delete_circle: true}} ->
          RestAdapter.json(conn, %{})

        %{errors: errors} ->
          RestAdapter.error_fn({:error, errors}, conn)

        _ ->
          RestAdapter.error_fn({:error, :unexpected_response}, conn)
      end
    end

    @doc """
    Get accounts in a list.

    Returns an array of Mastodon Account objects for all members of the list.

    Endpoint: GET /api/v1/lists/:id/accounts
    """
    @graphql "query ($circle_id: ID!, $limit: Int, $after: String, $before: String) {
      circle_members(circle_id: $circle_id, limit: $limit, after: $after, before: $before) {
        entries {
          #{@circle_member}
        }
        page_info: pageInfo {
          has_next_page: hasNextPage
          has_previous_page: hasPreviousPage
          start_cursor: startCursor
          end_cursor: endCursor
        }
      }
    }"
    def list_accounts(id, params, conn) do
      limit = PaginationHelpers.validate_limit(params["limit"] || 40)

      # Build pagination params from Mastodon params
      pagination_params =
        %{"circle_id" => id, "limit" => limit}
        |> maybe_add_graphql_cursor(params, "max_id", "after")
        |> maybe_add_graphql_cursor(params, "since_id", "before")
        |> maybe_add_graphql_cursor(params, "min_id", "before")

      case graphql(conn, :list_accounts, pagination_params) do
        %{data: %{circle_members: %{entries: entries, page_info: page_info}}}
        when is_list(entries) ->
          accounts =
            entries
            |> Enum.map(fn member ->
              subject = Map.get(member, :subject)
              Mappers.Account.from_user(subject, skip_expensive_stats: true)
            end)
            |> Enum.reject(&is_nil/1)

          conn =
            if page_info do
              page_info_map = %{
                start_cursor: Map.get(page_info, :start_cursor),
                end_cursor: Map.get(page_info, :end_cursor),
                cursor_fields: [id: :desc]
              }

              PaginationHelpers.add_simple_link_headers(conn, params, page_info_map, entries)
            else
              conn
            end

          RestAdapter.json(conn, accounts)

        %{errors: errors} ->
          RestAdapter.error_fn({:error, errors}, conn)

        _ ->
          RestAdapter.error_fn({:error, :not_found}, conn)
      end
    end

    @doc """
    Add accounts to a list.

    Expects `account_ids` param with an array of account IDs to add.

    Endpoint: POST /api/v1/lists/:id/accounts
    """
    @graphql "mutation ($circle_id: ID!, $subject_ids: [ID!]!) {
      add_to_circle(circle_id: $circle_id, subject_ids: $subject_ids)
    }"
    def add_to_list(id, params, conn) do
      modify_circle_members(conn, id, params, :add_to_list, :add_to_circle)
    end

    @doc """
    Remove accounts from a list.

    Expects `account_ids` param with an array of account IDs to remove.

    Endpoint: DELETE /api/v1/lists/:id/accounts
    """
    @graphql "mutation ($circle_id: ID!, $subject_ids: [ID!]!) {
      remove_from_circle(circle_id: $circle_id, subject_ids: $subject_ids)
    }"
    def remove_from_list(id, params, conn) do
      modify_circle_members(conn, id, params, :remove_from_list, :remove_from_circle)
    end

    @doc """
    Get the timeline for a list (posts from list members).

    Returns statuses from accounts in the specified list.
    Delegates to Social adapter's feed function with subject_circles filter.

    Endpoint: GET /api/v1/timelines/list/:list_id
    """
    def list_timeline(list_id, params, conn) do
      # Delegate to Social adapter with subject_circles filter
      alias Bonfire.Social.API.GraphQLMasto.Adapter, as: SocialAdapter

      limit = PaginationHelpers.validate_limit(params["limit"] || 20)

      # Extract pagination cursors from Mastodon params
      cursors = extract_mastodon_pagination_cursors(params)

      # Build limit param based on cursor direction (first for forward, last for backward)
      limit_param =
        cond do
          Map.has_key?(cursors, :after) -> %{first: limit}
          Map.has_key?(cursors, :before) -> %{last: limit}
          true -> %{first: limit}
        end

      # Use subject_circles filter to show posts from users in this list (circle)
      feed_params =
        %{
          "filter" => %{
            "subject_circles" => [list_id],
            "time_limit" => 0,
            "feed_name" => nil
          }
        }
        |> Map.merge(limit_param)
        |> Map.merge(cursors)

      SocialAdapter.feed(feed_params, conn)
    end

    defp with_valid_title(params, conn, fun) do
      title = params["title"]

      if is_nil(title) or String.trim(title) == "" do
        RestAdapter.error_fn({:error, :unprocessable_entity}, conn)
      else
        fun.(title)
      end
    end

    # Shared helper for add/remove circle members operations
    defp modify_circle_members(conn, id, params, query_name, data_key) do
      account_ids = params["account_ids"] || []

      case graphql(conn, query_name, %{"circle_id" => id, "subject_ids" => account_ids}) do
        %{data: data} when is_map(data) ->
          if Map.get(data, data_key) == true do
            RestAdapter.json(conn, %{})
          else
            RestAdapter.error_fn({:error, :unexpected_response}, conn)
          end

        %{errors: errors} ->
          RestAdapter.error_fn({:error, errors}, conn)

        _ ->
          RestAdapter.error_fn({:error, :unexpected_response}, conn)
      end
    end

    # Add cursor to GraphQL params (string params)
    defp maybe_add_graphql_cursor(params, mastodon_params, mastodon_key, graphql_key) do
      case mastodon_params[mastodon_key] do
        id when is_binary(id) and id != "" ->
          case encode_encircle_cursor(id) do
            {:ok, cursor} -> Map.put(params, graphql_key, cursor)
            _ -> params
          end

        _ ->
          params
      end
    end

    # Encode cursor for Encircle pagination (uses simple :id format)
    defp encode_encircle_cursor(id) when is_binary(id),
      do: PaginationHelpers.encode_cursor(id, %{id: id})

    defp encode_encircle_cursor(_), do: {:error, :invalid_id}

    # Extract Mastodon pagination cursors and convert to GraphQL cursor format
    defp extract_mastodon_pagination_cursors(params) do
      params
      |> Map.take(["max_id", "since_id", "min_id"])
      |> Enum.reduce(%{}, fn
        {"max_id", id}, acc when is_binary(id) and id != "" ->
          case encode_id_as_cursor(id) do
            {:ok, cursor} -> Map.put(acc, :after, cursor)
            _ -> acc
          end

        {"min_id", id}, acc when is_binary(id) and id != "" ->
          case encode_id_as_cursor(id) do
            {:ok, cursor} -> Map.put(acc, :before, cursor)
            _ -> acc
          end

        {"since_id", id}, acc when is_binary(id) and id != "" ->
          # Only use since_id if min_id not already set
          if Map.has_key?(acc, :before) do
            acc
          else
            case encode_id_as_cursor(id) do
              {:ok, cursor} -> Map.put(acc, :before, cursor)
              _ -> acc
            end
          end

        _, acc ->
          acc
      end)
    end

    # Encode a plain ID as a GraphQL cursor
    defp encode_id_as_cursor(id) when is_binary(id),
      do: PaginationHelpers.encode_cursor(id, %{{:activity, :id} => id})

    defp encode_id_as_cursor(_), do: {:error, :invalid_id}
  end
end
