defmodule Bonfire.Boundaries.Web.SetBoundariesLive do
  use Bonfire.UI.Common.Web, :stateless_component
  use Bonfire.Common.Utils

  prop create_object_type, :any, default: nil
  prop to_boundaries, :any, default: nil
  prop preset_boundary, :any, default: nil
  prop to_circles, :list, default: []
  prop showing_within, :any, default: nil
  prop show_select_recipients, :boolean, default: false
  prop open_boundaries, :boolean, default: false
  prop hide_breakdown, :boolean, default: false
  prop setting_boundaries, :boolean, default: false
  prop click_override, :boolean, default: false

  @form_input_name to_string(__MODULE__)
  @presets ["public", "local", "mentions", "custom"]

  def presets, do: @presets

  def reject_presets(to_boundaries)
      when is_list(to_boundaries) and to_boundaries != [] and to_boundaries != [nil],
      do: Keyword.drop(to_boundaries, presets())

  def reject_presets(_), do: []

  def boundaries_to_preset(to_boundaries) do
    to_boundaries
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

  def handle_info(%LiveSelect.ChangeMsg{text: search} = change_msg, socket) do
    current_user = current_user(socket)

    (Bonfire.Boundaries.Acls.list_my(current_user, search: search) ++
       Bonfire.Boundaries.Circles.list_my(current_user, search: search) ++
       Bonfire.Me.Users.search(search))
    |> results_for_multiselect()
    |> LiveSelect.update_options(change_msg, ...)

    {:noreply, socket}
  end

  def results_for_multiselect(results) do
    results
    |> Enum.map(fn
      %Bonfire.Data.AccessControl.Acl{} = acl ->
        {e(acl, :named, :name, nil) || e(acl, :sterotyped, :named, :name, nil),
         %{id: e(acl, :id, nil), field: :to_boundaries}}

      %Bonfire.Data.AccessControl.Circle{} = circle ->
        {e(circle, :named, :name, nil) || e(circle, :sterotyped, :named, :name, nil),
         %{id: e(circle, :id, nil), field: :to_circles}}

      user ->
        {e(user, :profile, :name, nil),
         %{
           id: e(user, :id, nil),
           field: :to_circles,
           icon: e(user, :profile, :icon, nil),
           username: e(user, :character, :username, nil)
         }}
    end)
    # Filter to remove any nils
    |> Enum.filter(fn {name, _} -> name != nil end)
    |> debug()
  end

  def handle_event(
        "multi_select",
        %{data: data, text: text},
        socket
      ) do
    # debug(data, text)

    field = maybe_to_atom(e(data, "field", :to_boundaries))

    appended_data =
      case field do
        :to_boundaries ->
          e(socket.assigns, field, [{"public", l("Public")}]) ++
            [{data["id"], data |> Enum.into(%{name: text})}]

        _ ->
          e(socket.assigns, field, []) ++ [{data |> Enum.into(%{name: text}), data["id"]}]
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
