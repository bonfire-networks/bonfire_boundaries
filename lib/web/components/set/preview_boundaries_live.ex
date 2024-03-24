defmodule Bonfire.Boundaries.Web.PreviewBoundariesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  # alias Bonfire.Boundaries.Roles

  declare_module_optional(l("Preview boundaries in composer"),
    description:
      l(
        "Adds a button to calculate and display how boundaries will be applied for a specific user."
      )
  )

  prop preview_boundary_for_id, :any, default: nil
  prop preview_boundary_for_username, :any, default: nil
  prop preview_boundary_verbs, :any, default: nil

  prop to_boundaries, :any, default: nil
  prop boundary_preset, :any, default: nil
  prop to_circles, :list, default: []

  def update(
        %{preview_boundary_for_id: preview_boundary_for_id} = assigns,
        %{assigns: %{preview_boundary_for_id: preview_boundary_for_id}} = socket
      ) do
    {
      :ok,
      socket
      |> assign(assigns)
    }
  end

  def update(%{preview_boundary_for_id: preview_boundary_for_id} = assigns, socket)
      when not is_nil(preview_boundary_for_id) do
    {
      :ok,
      socket
      |> assign(assigns)
      |> preview(preview_boundary_for_id, assigns[:preview_boundary_for_username])
      #  |> debug()
    }
  end

  def update(assigns, socket) do
    # current_user =(current_user(assigns) || current_user(socket.assigns))

    # params = e(assigns, :__context__, :current_params, %{})

    # available_verbs = Bonfire.Boundaries.Verbs.list(:code, :id)
    # |> debug("available_verbs")

    # available_verbs =
    #   if scope != :instance do
    #     instance_verbs =
    #       Bonfire.Boundaries.Verbs.list(:instance, :id)
    #       |> debug()

    #     available_verbs
    #     |> Enum.reject(&(elem(&1, 0) in instance_verbs))
    #   else
    #     available_verbs
    #   end
    #   |> debug()

    {
      :ok,
      socket
      |> assign(assigns)
      |> assign(
        #  cannot_role_verbs: Bonfire.Boundaries.Roles.cannot_role_verbs(),
        all_verbs: Bonfire.Boundaries.Verbs.verbs()
        # available_verbs: available_verbs
      )
      # |> preview(nil, l("guests"))
      #  |> debug()
    }
  end

  def handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket) do
    Utils.maybe_apply(
      Bonfire.Me.Users,
      :search,
      [search]
    )
    |> Bonfire.UI.Common.SelectRecipientsLive.results_for_multiselect()
    |> maybe_send_update(LiveSelect.Component, live_select_id, options: ...)

    {:noreply, socket}
  end

  def handle_event(
        "multi_select",
        %{data: %{"id" => id, "username" => username}},
        socket
      ) do
    {:noreply, preview(socket, id, username)}
  end

  def preview(socket, id, username) do
    current_user = current_user(socket.assigns)

    boundaries =
      Enum.map(
        List.wrap(
          e(socket.assigns, :boundary_preset, nil) || e(socket.assigns, :to_boundaries, [])
        ),
        fn
          {slug, _} -> slug
          slug -> slug
        end
      )
      |> debug("bbb")

    opts = [
      preview_for_id: id,
      boundary: e(boundaries, "mentions"),
      to_circles: e(socket.assigns, :to_circles, []),
      context_id: e(socket.assigns, :context_id, nil)
      # TODO: also calculate mentions from current draft text to take those into account in boundary calculation
      # mentions: [],
      # reply_to_id: e(socket.assigns, :reply_to_id, nil),
    ]

    with {:ok, verbs} <-
           Bonfire.Boundaries.Acls.preview(current_user, opts)
           |> debug("preview") do
      role = Bonfire.Boundaries.Roles.preset_boundary_role_from_acl(verbs)

      role_name =
        case role do
          {role_name, _permissions} -> role_name
          _ -> nil
        end

      socket
      |> assign(
        role_name: role_name,
        preview_boundary_for_username: username,
        preview_boundary_for_id: id || :guests,
        preview_boundary_verbs: verbs
      )

      # |> push_event("change", "#smart_input")
    end
  end

  # def preview(socket, id, username), do: socket
end
