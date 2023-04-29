defmodule Bonfire.Boundaries.LiveHandlerTest do
  use Bonfire.Boundaries.ConnCase, async: true
  alias Bonfire.Social.Fake
  alias Bonfire.Social.Posts
  alias Bonfire.Social.Boosts
  alias Bonfire.Social.Follows
  import Bonfire.Common.Enums
  alias Bonfire.Boundaries.{Circles, Acls, Grants}

  describe "Basic Circle actions" do
    test "Create a circle works" do
      account = fake_account!()
      me = fake_user!(account)
      conn = conn(user: me, account: account)
      next = "/boundaries/circles"
      {:ok, view, _html} = live(conn, next)

      view
      |> element("[data-id=new_circle] > div:first-child")
      |> render_click()

      assert view |> has_element?("button[data-role=new_circle_submit]")

      circle_name = "Friends"

      {:ok, circle_view, html} =
        view
        |> form("#modal_box", named: %{name: circle_name})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Circle created!"
      assert html =~ circle_name
      assert circle_view |> has_element?("h1[data-role=circle_title]")
    end

    test "Add a user to an existing circle works" do
      # create a bunch of users
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      # create a circle
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
      # navigate to the circle page
      conn = conn(user: me, account: account)
      next = "/boundaries/circle/#{circle.id}"
      {:ok, view, _html} = live(conn, next)
      # add alice to the circle via the input form
      assert view
             |> form("#edit_circle_participant")
             |> render_change(%{id: alice.id})

      assert render(view) =~ "Added to circle!"
    end

    test "Remove a user from a circle works" do
      # create a bunch of users
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      # create a circle
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
      {:ok, _} = Circles.add_to_circles(alice, circle)
      # navigate to the circle page
      conn = conn(user: me, account: account)
      next = "/boundaries/circle/#{circle.id}"
      {:ok, view, _html} = live(conn, next)

      assert view
             |> element("button[data-role=remove_user]")
             |> render_click()

      assert render(view) =~ "Removed from circle!"
    end

    test "Edit circle name works" do
      # create a bunch of users
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      # create a circle
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
      {:ok, _} = Circles.add_to_circles(alice, circle)
      # navigate to the circle page
      conn = conn(user: me, account: account)
      next = "/boundaries/circle/#{circle.id}"
      {:ok, view, _html} = live(conn, next)
      # open_browser(view)
      view
      |> element("li[data-role=edit_circle_name] div[data-role=open_modal]")
      |> render_click()

      new_circle_name = "friends"

      view
      |> form("#modal_box", named: %{name: new_circle_name})
      |> render_submit(%{id: circle.id})

      assert render(view) =~ "Edited!"
      # WIP ERROR TEST: the circle name is not updated in the view
      # assert render(view) =~ new_circle_name
    end

    test "delete circle works" do
      # create a bunch of users
      account = fake_account!()
      me = fake_user!(account)
      # create a circle
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
      # navigate to the circle page
      conn = conn(user: me, account: account)
      next = "/boundaries/circle/#{circle.id}"
      {:ok, view, _html} = live(conn, next)
      # open_browser(view)
      view
      |> element("li[data-role=delete_circle] div[data-role=open_modal]")
      |> render_click()

      assert {:ok, circles, _html} =
               view
               |> element("button[data-role=confirm_delete_circle]")
               |> render_click()
               |> follow_redirect(conn, "/boundaries/circles")

      assert render(circles) =~ "Deleted"
      # WIP ERROR TEST: the circle name is not updated in the view
      # assert render(view) =~ new_circle_name
    end
  end

  describe "Basic Boundaries actions" do
    test "Create a boundary works" do
      account = fake_account!()
      me = fake_user!(account)
      conn = conn(user: me, account: account)
      next = "/boundaries/acls"
      {:ok, view, _html} = live(conn, next)

      view
      |> element("[data-id=new_acl] div[data-role=open_modal]")
      |> render_click()

      assert view |> has_element?("button[data-role=new_acl_submit]")

      acl_name = "meme"

      {:ok, acl_view, html} =
        view
        |> form("#modal_box", named: %{name: acl_name})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Boundary created!"
      assert html =~ acl_name
    end

    test "Add a user and assign a role to a boundary works" do
      # create a bunch of users
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      # create a boundary
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
      # navigate to the boundary page
      conn = conn(user: me, account: account)
      next = "/boundaries/acl/#{acl.id}"
      {:ok, view, _html} = live(conn, next)
      # add alice to the boundary via the input form
      assert view
             |> form("#edit_acl_members")
             |> render_change(%{id: alice.id})

      assert render(view) =~ "finish adding it to the boundary"

      assert view
             |> form("#edit_grants")
             |> render_change(%{to_circles: %{alice.id => "administer"}})

      # open_browser(view)

      assert render(view) =~ "Permission edited"
    end

    test "Remove a user from a boundary works" do
      # create a bunch of users
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      # create a boundary
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
      Grants.grant_role(alice.id, acl.id, "contribute", current_user: me)
      # navigate to the boundary page
      conn = conn(user: me, account: account)
      next = "/boundaries/acl/#{acl.id}"
      {:ok, view, _html} = live(conn, next)

      view
      |> element("li[data-role=remove_from_boundary] div[data-role=open_modal]")
      |> render_click()

      assert view
             |> element("button[data-role=remove_from_boundary_btn]")
             |> render_click()

      assert render(view) =~ "Removed from boundary"
    end

    test "Add a circle and assign a role to a boundary works" do
      # create a bunch of users
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      # create a circle
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
      # create a boundary
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
      # navigate to the boundary page
      conn = conn(user: me, account: account)
      next = "/boundaries/acl/#{acl.id}"
      {:ok, view, _html} = live(conn, next)
      # add circle family to the boundary via the input form
      assert view
             |> form("#edit_acl_members")
             |> render_change(%{id: circle.id})

      assert render(view) =~ "finish adding it to the boundary"

      assert view
             |> form("#edit_grants")
             |> render_change(%{to_circles: %{circle.id => "administer"}})

      # open_browser(view)

      assert render(view) =~ "Permission edited"
    end

    test "Remove a circle from a boundary works" do
      # create a bunch of users
      account = fake_account!()
      me = fake_user!(account)
      # create a circle
      {:ok, circle} = Circles.create(me, %{named: %{name: "family"}})
      # create a boundary
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
      Grants.grant_role(circle.id, acl.id, "contribute", current_user: me)
      # navigate to the boundary page
      conn = conn(user: me, account: account)
      next = "/boundaries/acl/#{acl.id}"
      {:ok, view, _html} = live(conn, next)

      view
      |> element("li[data-role=remove_from_boundary] div[data-role=open_modal]")
      |> render_click()

      assert view
             |> element("button[data-role=remove_from_boundary_btn]")
             |> render_click()

      assert render(view) =~ "Removed from boundary!"
    end

    test "Edit a role in a boundary works" do
      # create a bunch of users
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      # create a boundary
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
      # navigate to the boundary page
      conn = conn(user: me, account: account)
      next = "/boundaries/acl/#{acl.id}"
      {:ok, view, _html} = live(conn, next)
      # add alice to the boundary via the input form
      assert view
             |> form("#edit_acl_members")
             |> render_change(%{id: alice.id})

      assert render(view) =~ "finish adding it to the boundary"

      assert view
             |> form("#edit_grants")
             |> render_change(%{to_circles: %{alice.id => "negative_participate"}})

      assert render(view) =~ "Permission edited"

      # reload
      next = "/boundaries/acl/#{acl.id}"
      {:ok, view, _html} = live(conn, next)

      # check role is correct
      assert view
             |> element("#edit_grants ul:first-child select option[selected]")
             |> render() =~ "Cannot Participate"

      # downgrade role
      assert view
             |> form("#edit_grants")
             |> render_change(%{to_circles: %{alice.id => "negative_interact"}})

      assert render(view) =~ "Permission edited"

      # open_browser(view)

      # reload
      next = "/boundaries/acl/#{acl.id}"
      {:ok, view, _html} = live(conn, next)

      # check role is correct
      assert view
             |> element("#edit_grants ul:first-child select option[selected]")
             |> render() =~ "Cannot Interact"
    end

    test "Add a user, assign a role to a boundary, and then edit/downgrade that boundary works" do
      # create a bunch of users
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      # create a boundary
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
      # navigate to the boundary page
      conn = conn(user: me, account: account)
      next = "/boundaries/acl/#{acl.id}"
      {:ok, view, _html} = live(conn, next)
      # add alice to the boundary via the input form
      assert view
             |> form("#edit_acl_members")
             |> render_change(%{id: alice.id})

      assert render(view) =~ "finish adding it to the boundary"

      assert view
             |> form("#edit_grants")
             |> render_change(%{to_circles: %{alice.id => "negative_administer"}})

      assert render(view) =~ "Permission edited"

      # reload
      next = "/boundaries/acl/#{acl.id}"
      {:ok, view, _html} = live(conn, next)

      # check role is correct
      assert view
             |> element("#edit_grants ul:first-child select option[selected]")
             |> render() =~ "Cannot Administer"

      # downgrade role
      assert view
             |> form("#edit_grants")
             |> render_change(%{to_circles: %{alice.id => "negative_read"}})

      assert render(view) =~ "Permission edited"

      # open_browser(view)

      # reload
      next = "/boundaries/acl/#{acl.id}"
      {:ok, view, _html} = live(conn, next)

      # check role is correct
      assert view
             |> element("#edit_grants ul:first-child select option[selected]")
             |> render() =~ "Cannot Read"
    end

    test "Edit Settings to a boundary works" do
      # create a bunch of users
      account = fake_account!()
      me = fake_user!(account)
      alice = fake_user!(account)
      # create a circle
      {:ok, acl} = Acls.create(%{named: %{name: "meme"}}, current_user: me)
      # navigate to the acl settings page
      conn = conn(user: me, account: account)
      next = "/boundaries/acl/#{acl.id}/settings"
      {:ok, view, _html} = live(conn, next)
      # open_browser(view)
      new_acl_name = "friends"

      assert view
             |> form("#edit_acl", named: %{name: new_acl_name})
             |> render_submit()

      assert render(view) =~ "Edited!"
      assert render(view) =~ new_acl_name

      # WIP: the view is not updated instantly
      view
      |> element("div[data-role=delete_boundary_modal] div[data-role=open_modal]")
      |> render_click()

      assert {:ok, acls, _html} =
               view
               |> element("button[data-id=delete_boundary]")
               |> render_click()
               |> follow_redirect(conn, "/boundaries/acls")

      assert render(acls) =~ "Deleted"
    end
  end
end
