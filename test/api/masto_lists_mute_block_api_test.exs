# SPDX-License-Identifier: AGPL-3.0-only
if Application.compile_env(:bonfire_boundaries, :modularity) != :disabled do
  defmodule Bonfire.Boundaries.Web.MastoListsMuteBlockApiTest do
    @moduledoc "Run with: just test extensions/bonfire_boundaries/test/api/masto_lists_mute_block_api_test.exs"

    use Bonfire.API.MastoApiCase, async: false

    @moduletag :masto_api

    setup %{conn: conn} do
      account = Bonfire.Me.Fake.fake_account!()
      user = Bonfire.Me.Fake.fake_user!(account)

      conn = masto_api_conn(conn, user: user, account: account)

      {:ok, conn: conn, user: user, account: account}
    end

    defp unauthenticated_conn do
      Phoenix.ConnTest.build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
    end

    describe "GET /api/v1/lists" do
      test "returns 200 with list", %{conn: conn} do
        response =
          conn
          |> get("/api/v1/lists")
          |> json_response(200)

        assert is_list(response)
      end

      test "requires authentication" do
        response =
          unauthenticated_conn()
          |> get("/api/v1/lists")
          |> json_response(401)

        assert response["error"]
      end
    end

    describe "POST /api/v1/lists" do
      test "creates a list and returns it", %{conn: conn} do
        response =
          conn
          |> post("/api/v1/lists", %{"title" => "Test List"})
          |> json_response(200)

        assert response["title"] == "Test List"
        assert Map.has_key?(response, "id")
      end
    end

    describe "GET /api/v1/mutes" do
      test "returns 200 with list", %{conn: conn} do
        response =
          conn
          |> get("/api/v1/mutes")
          |> json_response(200)

        assert is_list(response)
      end

      test "requires authentication" do
        response =
          unauthenticated_conn()
          |> get("/api/v1/mutes")
          |> json_response(401)

        assert response["error"]
      end
    end

    describe "POST /api/v1/accounts/:id/mute" do
      test "does not return 500", %{conn: conn} do
        other_account = Bonfire.Me.Fake.fake_account!()
        other_user = Bonfire.Me.Fake.fake_user!(other_account)

        conn = post(conn, "/api/v1/accounts/#{other_user.id}/mute")
        assert conn.status in [200, 404, 422]
      end
    end

    describe "GET /api/v1/blocks" do
      test "returns 200 with list", %{conn: conn} do
        response =
          conn
          |> get("/api/v1/blocks")
          |> json_response(200)

        assert is_list(response)
      end

      test "requires authentication" do
        response =
          unauthenticated_conn()
          |> get("/api/v1/blocks")
          |> json_response(401)

        assert response["error"]
      end
    end

    describe "POST /api/v1/accounts/:id/block" do
      test "does not return 500", %{conn: conn} do
        other_account = Bonfire.Me.Fake.fake_account!()
        other_user = Bonfire.Me.Fake.fake_user!(other_account)

        conn = post(conn, "/api/v1/accounts/#{other_user.id}/block")
        assert conn.status in [200, 404, 422]
      end
    end
  end
end
