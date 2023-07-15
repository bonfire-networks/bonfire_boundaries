defmodule Bonfire.Boundaries.Web.SetBoundariesLive do
  use Bonfire.UI.Common.Web, :stateless_component
  use Bonfire.Common.Utils

  prop create_object_type, :any, default: nil
  prop to_boundaries, :any, default: nil
  prop preset_boundary, :any, default: nil
  prop to_circles, :list, default: []
  prop exclude_circles, :list, default: []
  prop showing_within, :atom, default: nil
  prop show_select_recipients, :boolean, default: false
  prop open_boundaries, :boolean, default: false
  prop hide_breakdown, :boolean, default: false
  prop setting_boundaries, :boolean, default: false
  prop click_override, :boolean, default: false

  @presets ["public", "local", "mentions", "custom"]

  def presets, do: @presets

  def render(assigns) do
    assigns
    |> assign_new(:my_circles, fn -> list_my_circles(current_user(assigns[:__context__])) end)
    |> assign_new(:roles_for_dropdown, fn ->
      Bonfire.Boundaries.Roles.roles_for_dropdown(nil, scope: nil, context: assigns[:__context__])
    end)
    |> render_sface()
  end

  def reject_presets(to_boundaries)
      when is_list(to_boundaries) and to_boundaries != [] and to_boundaries != [nil],
      do: Keyword.drop(to_boundaries, presets())

  def reject_presets(_), do: []

  def boundaries_to_preset(to_boundaries) do
    List.wrap(to_boundaries)
    |> Enum.filter(fn
      {x, _} when x in @presets -> true
      _ -> false
    end)
    |> List.first()
    |> debug()
  end

  # def set_clean_boundaries(to_boundaries, "custom", _name) do
  #   Keyword.drop(to_boundaries, ["public", "local", "mentions"])
  # end

  def set_clean_boundaries(to_boundaries, acl_id, name)
      when acl_id in @presets do
    reject_presets(to_boundaries) ++
      [{acl_id, name}]
  end

  def set_clean_boundaries(to_boundaries, acl_id, name) do
    to_boundaries ++ [{acl_id, name}]
  end

  def results_for_multiselect(results, circle_field \\ :to_circles) do
    results
    |> Enum.map(fn
      %Bonfire.Data.AccessControl.Acl{} = acl ->
        name = e(acl, :named, :name, nil) || e(acl, :stereotyped, :named, :name, nil)

        {name,
         %{
           id: e(acl, :id, nil),
           field: :to_boundaries,
           name: name
         }}

      %Bonfire.Data.AccessControl.Circle{} = circle ->
        name = e(circle, :named, :name, nil) || e(circle, :stereotyped, :named, :name, nil)

        {name,
         %{
           id: e(circle, :id, nil),
           field: circle_field,
           name: name
         }}

      user ->
        name = e(user, :profile, :name, nil)
        username = e(user, :character, :username, nil)

        {"#{name} - #{username}",
         %{
           id: e(user, :id, nil),
           field: circle_field,
           icon: Media.avatar_url(user),
           name: name,
           username: username
         }}
    end)
    # Filter to remove any nils
    |> Enum.filter(fn {name, _} -> name != nil end)
    # Reduce the results to show in dropdown for clarity to 4 items
    |> Enum.take(4)

    # |> debug()
  end

  # def list_my_boundaries(socket) do
  #   current_user = current_user(socket)
  #   Bonfire.Boundaries.Acls.list_my(current_user)
  # end

  def list_my_circles(scope) do
    # TODO: load using LivePlug to avoid re-loading on render?
    Bonfire.Boundaries.Circles.list_my_with_global(scope,
      exclude_block_stereotypes: true
    )
  end

  def live_select_change(live_select_id, search, circle_field, socket) do
    current_user = current_user(socket)
    # Bonfire.Boundaries.Acls.list_my(current_user, search: search) ++
    (Bonfire.Boundaries.Circles.list_my_with_global(
       [current_user, Bonfire.Boundaries.Fixtures.activity_pub_circle()],
       search: search
     ) ++
       Bonfire.Me.Users.search(search))
    |> results_for_multiselect(circle_field)
    |> maybe_send_update(LiveSelect.Component, live_select_id, options: ...)

    {:noreply, socket}
  end

  def do_handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket) do
    live_select_change(live_select_id, search, :to_circles, socket)
  end

  def do_handle_event(
        "multi_select",
        %{data: data, text: text},
        socket
      ) do
    # debug(data, text)

    field =
      maybe_to_atom(e(data, "field", :to_boundaries))
      |> debug("field")

    appended_data =
      case field do
        :to_boundaries ->
          e(socket.assigns, field, [{"public", l("Public")}]) ++
            [{data["id"], data}]

        _ ->
          e(socket.assigns, field, []) ++ [{data, data["id"]}]
      end
      |> Enum.uniq()

    {:noreply,
     socket
     |> assign(
       field,
       appended_data
     )}
  end

  def handle_event("tagify_add", attrs, socket) do
    handle_event("select_boundary", attrs, socket)
  end

  def handle_event("tagify_remove", attrs, socket) do
    handle_event("remove_boundary", attrs, socket)
  end
end
