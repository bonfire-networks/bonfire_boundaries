defmodule Bonfire.Boundaries.Web.MyCirclesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.LiveHandler

  prop setting_boundaries, :boolean, default: false
  prop section, :any, default: nil
  prop parent_back, :any, default: nil
  prop scope, :atom, default: nil

  def update(
        %{scope: scope} = assigns,
        %{assigns: %{loaded: true, scope: existing_scope}} = socket
      )
      when scope == existing_scope do
    {:ok,
     assign(
       socket,
       assigns
     )}
  end

  def update(assigns, socket) do
    current_user = current_user(assigns)
    scope = e(assigns, :scope, nil) || e(socket.assigns, :scope, nil)

    user =
      if scope == :instance and
           (Integration.is_admin?(current_user) ||
              Bonfire.Boundaries.can?(current_user, :appoint, :instance)),
         do: Bonfire.Boundaries.Fixtures.admin_circle(),
         else: current_user

    # |> IO.inspect
    circles =
      Bonfire.Boundaries.Circles.list_my_with_counts(user)
      |> repo().maybe_preload(encircles: [subject: [:profile]])

    debug(circles, "Circles")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       loaded: true,
       circles: circles,
       settings_section_title: "Create and manage your circles",
       settings_section_description: "Create and manage your circles."
     )}
  end

  # TODO
  def handle_event("back", _, socket) do
    {:noreply, assign(socket, :section, nil)}
  end

  def handle_event(action, attrs, socket),
    do:
      Bonfire.UI.Common.LiveHandlers.handle_event(
        action,
        attrs,
        socket,
        __MODULE__
      )
end