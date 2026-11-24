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

    # AbsintheClient doesn't call schema's context/1, so we add Dataloader here
    def absinthe_pipeline(schema, opts) do
      context = Keyword.get(opts, :context, %{})

      context_with_loader =
        if Map.has_key?(context, :loader),
          do: context,
          else: schema.context(context)

      AbsintheClient.default_pipeline(schema, Keyword.put(opts, :context, context_with_loader))
    end

    alias Bonfire.API.MastoCompat.{Fragments, Mappers, Schemas, PaginationHelpers}

    # User profile fragment inlined for compile-order independence
    @account_fields Fragments.account_fields()

    # Mastodon's mutes and blocks, paged by account id: one more than `limit` is asked for, to know whether a next page exists
    defp list_restricted_accounts(conn, params, query_name, data_key) do
      current_user = conn.assigns[:current_user]

      if is_nil(current_user) do
        RestAdapter.error_fn({:error, :unauthorized}, conn)
      else
        limit = PaginationHelpers.validate_limit(params["limit"])

        variables =
          %{"limit" => limit + 1}
          |> PaginationHelpers.maybe_add_cursor(params, "max_id", "after")
          |> PaginationHelpers.maybe_add_cursor(params, "since_id", "before")
          |> PaginationHelpers.maybe_add_cursor(params, "min_id", "before")

        case graphql(conn, query_name, variables) do
          %{data: data} when is_map(data) ->
            users = Map.get(data, data_key, []) || []

            newer? = Map.has_key?(variables, "before")
            accounts = page_accounts(users, limit, newer?)

            # `add_simple_link_headers/4` takes the cursors from the first and last account
            page_info = %{has_next_page: newer? or length(users) > limit}

            conn
            |> PaginationHelpers.add_simple_link_headers(params, page_info, accounts)
            |> RestAdapter.json(accounts)

          %{errors: errors} ->
            error(errors, "GraphQL error in #{query_name}")
            RestAdapter.error_fn({:error, errors}, conn)

          other ->
            error(other, "Unexpected GraphQL response in #{query_name}")
            RestAdapter.json(conn, [])
        end
      end
    end

    # with `min_id`/`since_id` the extra row is on the newer side: keep the `limit` closest to the cursor (an older page always exists then: the cursor's own account)
    defp page_accounts(users, limit, newer?) do
      users
      |> Enum.take(if newer?, do: -limit, else: limit)
      |> Enum.map(&Mappers.Account.from_user/1)
      |> Enum.reject(&is_nil/1)
    end

    @graphql "query ($limit: Int, $after: ID, $before: ID) {
      muted_users(exclude_blocked: true, limit: $limit, after: $after, before: $before) {
        #{@account_fields}
      }
    }"
    @doc "List muted accounts for current user: silenced and not blocked, as Mastodon keeps the two apart"
    def mutes(params, conn), do: list_restricted_accounts(conn, params, :mutes, :muted_users)

    @graphql "query ($limit: Int, $after: ID, $before: ID) {
      blocked_users(limit: $limit, after: $after, before: $before) {
        #{@account_fields}
      }
    }"
    @doc "List blocked accounts for current user"
    def blocks(params, conn), do: list_restricted_accounts(conn, params, :blocks, :blocked_users)

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
            respond_with_relationship(conn, current_user, target_id)

          %{errors: _errors} when action in [:unmute, :unblock] ->
            # Mastodon API expects unmute/unblock to be idempotent
            respond_with_relationship(conn, current_user, target_id)

          %{errors: errors} ->
            RestAdapter.error_fn({:error, errors}, conn)

          _ ->
            RestAdapter.error_fn({:error, :unexpected_response}, conn)
        end
      end
    end

    defp respond_with_relationship(conn, user, target_id) do
      case read_relationship(user, target_id) do
        {:ok, relationship} -> RestAdapter.json(conn, relationship)
        {:error, error} -> RestAdapter.error_fn({:error, error}, conn)
      end
    end

    @relationship_query "query($id: ID!, $target: ID!) { user(filter: {id: $id}) { relationship(with: $target) { following followed requested ghosting silencing } } }"

    @doc "The Mastodon Relationship of `user` to `target_id`, read through GraphQL; `notifying?` is the caller's to know (bells live in `bonfire_notify`)."
    def read_relationship(user, target_id, notifying? \\ false) do
      case Absinthe.run(@relationship_query, Bonfire.API.GraphQL.Schema,
             variables: %{"id" => user.id, "target" => target_id},
             context: Bonfire.API.GraphQL.Schema.context(%{current_user: user})
           ) do
        {:ok, %{data: %{"user" => %{"relationship" => relationship}}}}
        when is_map(relationship) ->
          {:ok,
           Schemas.Relationship.new(
             %{
               "id" => to_string(target_id),
               "following" => relationship["following"],
               "followed_by" => relationship["followed"],
               "requested" => relationship["requested"],
               "notifying" => notifying?
             }
             # the same rule as /relationships, /blocks and /mutes
             |> Map.merge(
               Schemas.Relationship.restrictions(relationship["ghosting"], relationship["silencing"])
             )
           )}

        {:ok, %{errors: errors}} ->
          {:error, errors}

        _ ->
          {:error, :not_found}
      end
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
        #{@account_fields}
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
      if is_nil(conn.assigns[:current_user]) do
        RestAdapter.error_fn({:error, :unauthorized}, conn)
      else
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
      try do
        case graphql(conn, :delete_list, %{"id" => id}) do
          %{data: %{delete_circle: result}} when result not in [nil, false] ->
            RestAdapter.json(conn, %{})

          %{errors: errors} ->
            RestAdapter.error_fn({:error, errors}, conn)

          _ ->
            RestAdapter.error_fn({:error, :not_found}, conn)
        end
      rescue
        _ -> RestAdapter.error_fn({:error, :not_found}, conn)
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
      if not Bonfire.Common.Types.is_uid?(id) do
        RestAdapter.error_fn({:error, :not_found}, conn)
      else
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
              |> Enum.flat_map(fn member ->
                subject = Map.get(member, :subject) || Map.get(member, "subject")

                case subject && Mappers.Account.from_user(subject) do
                  nil -> []
                  account -> [account]
                end
              end)

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

    @doc """
    Get lists (circles) owned by the current user that contain the specified account.

    Mastodon API: GET /api/v1/accounts/:id/lists
    Returns an array of List objects (or empty array if account is not in any lists).
    """
    def account_lists(%{"id" => target_id}, conn) do
      RestAdapter.with_current_user(conn, fn current_user ->
        circles =
          Bonfire.Boundaries.Circles.circles_containing_subject(current_user, target_id)

        lists =
          circles
          |> Enum.map(&Mappers.List.from_circle/1)
          |> Enum.reject(&is_nil/1)

        RestAdapter.json(conn, lists)
      end)
    end
  end
end
