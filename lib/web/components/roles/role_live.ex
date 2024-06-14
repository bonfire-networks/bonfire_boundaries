defmodule Bonfire.Boundaries.Web.RoleLive do
  use Bonfire.UI.Common.Web, :stateful_component

  def update(assigns, socket) do
    current_user = current_user(assigns) || current_user(socket.assigns)

    params =
      e(assigns, :__context__, :current_params, %{})
      |> debug("current_params")

    id =
      e(params, "id", nil)
      |> debug("role_id")

    role = Bonfire.Boundaries.Roles.get(id, current_user: current_user)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       params: params,
       page_title: l("Role"),
       role: role
     )}
  end
end
