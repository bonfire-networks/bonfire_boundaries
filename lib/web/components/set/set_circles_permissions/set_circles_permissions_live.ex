defmodule Bonfire.Boundaries.Web.SetCirclesPermissionsLive do
  use Bonfire.UI.Common.Web, :stateful_component
  use Bonfire.Common.Utils

  # declare_module_optional(l("Custom boundaries in composer"),
  #   description:
  #     l(
  #       "Enable selecting custom roles for specific circles or users in the composer when drafting a post."
  #     )
  # )

  prop create_object_type, :any, default: nil
  prop to_boundaries, :any, default: nil
  prop boundary_preset, :any, default: nil
  prop to_circles, :list, default: []
  prop exclude_circles, :list, default: []

  prop my_circles, :list, default: nil

  prop showing_within, :atom, default: nil

  prop hide_breakdown, :boolean, default: false
  prop click_override, :boolean, default: false
  prop read_only, :boolean, default: false
  prop is_caretaker, :boolean, default: true

  @presets ["public", "local", "mentions", "custom"]
  def presets, do: @presets

  def render(%{read_only: false, my_circles: nil} = assigns) do
    # TODO: only load this once per persistent session, or when we open the composer
    assigns
    |> assign(:my_circles, list_my_circles(current_user(assigns[:__context__])))
    |> assign_new(:roles_for_dropdown, fn ->
      Bonfire.Boundaries.Roles.roles_for_dropdown(nil, scope: nil, context: assigns[:__context__])
    end)
    |> render_sface()
  end

  def render(assigns) do
    assigns
    |> assign_new(:roles_for_dropdown, fn -> [] end)
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
      x when x in @presets -> true
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
           name: name,
           type: "acl"
         }}

      %Bonfire.Data.AccessControl.Circle{} = circle ->
        name = e(circle, :named, :name, nil) || e(circle, :stereotyped, :named, :name, nil)

        {name,
         %{
           id: e(circle, :id, nil),
           field: circle_field,
           name: name,
           type: "circle"
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
           username: username,
           type: "user"
         }}
    end)
    # Filter to remove any nils
    |> Enum.filter(fn {name, _} -> name != nil end)
    # Reduce the results to show in dropdown for clarity to 4 items
    |> Enum.take(4)

    # |> debug()
  end

  # def list_my_boundaries(socket) do
  #   current_user = current_user(socket.assigns)
  #   Bonfire.Boundaries.Acls.list_my(current_user)
  # end

  def list_my_circles(scope) do
    # TODO: load using LivePlug to avoid re-loading on render?
    Bonfire.Boundaries.Circles.list_my(scope,
      exclude_stereotypes: true,
      exclude_built_ins: true
    )
  end

  def live_select_change(live_select_id, search, circle_field, socket) do
    current_user = current_user(socket.assigns)
    # Bonfire.Boundaries.Acls.list_my(current_user, search: search) ++
    (Bonfire.Boundaries.Circles.list_my_with_global(
       [current_user, Bonfire.Boundaries.Fixtures.activity_pub_circle()],
       search: search
     ) ++
       Common.Utils.maybe_apply(
         Bonfire.Me.Users,
         :search,
         [search]
       ))
    |> results_for_multiselect(circle_field)
    |> maybe_send_update(LiveSelect.Component, live_select_id, options: ...)

    {:noreply, socket}
  end

  def handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket) do
    live_select_change(live_select_id, search, :to_circles, socket)
  end

  def handle_event("multi_select", %{"add_circles" => circle_id}, socket) do
    debug(circle_id, "QUIII")
    circles_list = list_my_circles(current_user(socket.assigns))

    # Find the circle by ID
    circle = Enum.find(circles_list, fn c -> c.id == circle_id end)

    circles =
      e(socket.assigns, :to_circles, []) ++
        [{circle, nil}]

    {:noreply,
     socket
     |> assign(to_circles: circles)}
  end

  def acls_from_role(role) do
    {:ok, permissions, []} = Bonfire.Boundaries.Roles.verbs_for_role(maybe_to_atom(role), %{})
    permissions
  end

  def name(data) when is_binary(data), do: data
  def name(data) when is_tuple(data), do: elem(data, 1)

  def name(data) when is_map(data),
    do:
      e(data, :name, nil) || e(data, :profile, :name, nil) || e(data, :named, :name, nil) ||
        e(data, :stereotyped, :named, :name, nil)

  def name(data) do
    warn(data, "Dunno how to display")
    nil
  end

  def handle_event(
        "multi_select",
        %{data: data, text: _text},
        socket
      ) do
    # debug(data, text)

    field =
      maybe_to_atom(e(data, "field", :to_boundaries))
      |> debug("field")

    appended_data =
      case field do
        :to_boundaries ->
          # [{"public", l("Public")}]
          []
          |> (e(socket.assigns, field, ...) ++
                [{id(data), data}])

        :to_circles ->
          e(socket.assigns, field, []) ++
            [{data, nil}]

        :exclude_circles ->
          e(socket.assigns, field, []) ++
            [{data, nil}]

        _ ->
          e(socket.assigns, field, []) ++
            [{data, id(data)}]
      end
      |> debug("list")
      |> Enum.uniq()
      |> debug("uniq")

    {:noreply,
     socket
     |> assign(
       field,
       appended_data
     )
     |> assign_global(
       _already_live_selected_:
         Enum.uniq(e(socket.assigns, :__context, :_already_live_selected_, []) ++ [field])
     )}
  end

  def handle_event("tagify_add", attrs, socket) do
    handle_event("select_boundary", attrs, socket)
  end

  def handle_event("tagify_remove", attrs, socket) do
    handle_event("remove_boundary", attrs, socket)
  end
end
