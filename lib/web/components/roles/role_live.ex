defmodule Bonfire.Boundaries.Web.RoleLive do
  use Bonfire.UI.Common.Web, :stateful_component

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(page_title: l("Role"))}
  end

  # def update(assigns, socket) do
  #   current_user = current_user(assigns) 
  #   IO.inspect("QUIII")
  #   params = e(assigns, :__context__, :current_params, %{})

  #   id =
  #     e(params, "id", nil)
  #     |> debug()

  #   socket =
  #     socket
  #     |> assign(assigns)
  #     |> assign(
  #       loaded: true,
  #       page_title: l("Role - ") <> id,
  #       section: e(params, "section", "members")
  #     )

  # with {:ok, role} <-
  #        Bonfire.Boundaries.Verbs.get(id) do
  #   debug(role, "role")

  #   send_self(
  #     page_title: l("Role - ") <> id,
  #     role: role
  #   )

  #   {:ok,
  #    assign(
  #      socket,
  #      role: role,
  #      page_title: l("role")
  #    )}

  # else other ->
  #   error(other)
  #   {:ok, socket
  #     |> assign_flash(:error, l "Could not find circle")
  #     |> assign(
  #       circle: nil,
  #       members: [],
  #       suggestions: [],
  #       read_only: true
  #     )
  #     # |> redirect_to("/boundaries/circles")
  #   }
  # end
  # end
end
