defmodule Bonfire.Boundaries.Web.RolesTest do
  use Bonfire.Boundaries.ConnCase, async: true

  @moduletag :ui

  alias Bonfire.Social.Fake
  alias Bonfire.Posts
  alias Bonfire.Social.Boosts
  alias Bonfire.Social.Graph.Follows
  import Bonfire.Common.Enums
  alias Bonfire.Boundaries.{Circles, Acls, Grants, Roles}

  test "Create a role works" do
    me = fake_user!()
    conn = conn(user: me)
    next = "/boundaries/roles"
    {:ok, view, _html} = live(conn, next)

    view
    |> element("[data-role=new_role] div[data-role=open_modal]")
    |> render_click()

    assert view |> has_element?("button[data-role=new_role_submit]")

    name = "Tester"

    #       open_browser(view)

    {:ok, view, html} =
      view
      |> form("#new_role_form", name: name)
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Role created"
    #       open_browser(view)
    assert has_element?(view, "p", name)
    #       assert view |> has_element?("h1[data-role=circle_title]")
  end

  test "can edit role permissions" do
    me = fake_user!()
    name = "Tester"

    assert {:ok, role} =
             Roles.create(
               %{name: name},
               #       scope: me,
               current_user: me
             )

    conn = conn(user: me)

    next = "/boundaries/roles"
    {:ok, view, _html} = live(conn, next)

    assert has_element?(view, "p", name)

    # add a permission
    html =
      view
      |> form("form[data-id=role_#{name}_create")
      |> render_change(%{"role" => %{name => %{"create" => "1"}}})

    #       assert html =~ "Permission edited"
    #       open_browser(view)

    assert %{^name => %{can_verbs: [:create], cannot_verbs: []}} =
             Bonfire.Boundaries.Roles.role_verbs(:all,
               one_scope_only: true,
               #      scope: me,
               current_user: id(me),
               preload: true
             )

    #    |> IO.inspect(label: "yay1")

    # deny a permission
    html =
      view
      |> form("form[data-id=role_#{name}_read")
      |> render_change(%{"role" => %{name => %{"read" => "0"}}})

    #       assert html =~ "Permission edited"
    #       open_browser(view)

    assert %{^name => %{can_verbs: [:create], cannot_verbs: [:read]}} =
             Bonfire.Boundaries.Roles.role_verbs(:all,
               one_scope_only: true,
               #      scope: me,
               current_user: id(me),
               preload: true
             )

    #    |> IO.inspect(label: "yay0")

    # remove a permission
    html =
      view
      |> form("form[data-id=role_#{name}_create")
      |> render_change(%{"role" => %{name => %{"create" => ""}}})

    #       assert html =~ "Permission edited"
    #       open_browser(view)

    assert %{^name => %{can_verbs: [], cannot_verbs: [:read]}} =
             Bonfire.Boundaries.Roles.role_verbs(:all,
               one_scope_only: true,
               #      scope: me,
               current_user: id(me),
               preload: true
             )

    #    |> IO.inspect(label: "yayNIL")
  end
end
