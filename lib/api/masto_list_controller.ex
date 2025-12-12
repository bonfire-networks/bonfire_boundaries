if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.Boundaries.Web.MastoListController do
    @moduledoc """
    Mastodon-compatible Lists endpoints.

    Implements the lists API following Mastodon API conventions:
    - GET /api/v1/lists - Get all lists
    - POST /api/v1/lists - Create a new list
    - GET /api/v1/lists/:id - Get a specific list
    - PUT /api/v1/lists/:id - Update a list
    - DELETE /api/v1/lists/:id - Delete a list
    - GET /api/v1/lists/:id/accounts - Get accounts in a list
    - POST /api/v1/lists/:id/accounts - Add accounts to a list
    - DELETE /api/v1/lists/:id/accounts - Remove accounts from a list

    In Bonfire, Lists are implemented using Circles.
    """
    use Bonfire.UI.Common.Web, :controller
    import Untangle

    alias Bonfire.Boundaries.API.GraphQLMasto.Adapter

    @doc "Get all lists owned by the authenticated user"
    def index(conn, params) do
      debug(params, "GET /api/v1/lists")
      Adapter.lists(params, conn)
    end

    @doc "Create a new list"
    def create(conn, params) do
      debug(params, "POST /api/v1/lists")
      Adapter.create_list(params, conn)
    end

    @doc "Get a specific list by ID"
    def show(conn, %{"id" => id} = params) do
      debug(params, "GET /api/v1/lists/#{id}")
      Adapter.show_list(id, params, conn)
    end

    @doc "Update a list (change title)"
    def update(conn, %{"id" => id} = params) do
      debug(params, "PUT /api/v1/lists/#{id}")
      Adapter.update_list(id, params, conn)
    end

    @doc "Delete a list"
    def delete(conn, %{"id" => id} = params) do
      debug(params, "DELETE /api/v1/lists/#{id}")
      Adapter.delete_list(id, params, conn)
    end

    @doc "Get accounts in a list"
    def accounts(conn, %{"id" => id} = params) do
      debug(params, "GET /api/v1/lists/#{id}/accounts")
      Adapter.list_accounts(id, params, conn)
    end

    @doc "Add accounts to a list"
    def add_accounts(conn, %{"id" => id} = params) do
      debug(params, "POST /api/v1/lists/#{id}/accounts")
      Adapter.add_to_list(id, params, conn)
    end

    @doc "Remove accounts from a list"
    def remove_accounts(conn, %{"id" => id} = params) do
      debug(params, "DELETE /api/v1/lists/#{id}/accounts")
      Adapter.remove_from_list(id, params, conn)
    end
  end
end
