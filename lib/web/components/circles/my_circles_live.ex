defmodule Bonfire.Boundaries.Web.MyCirclesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  # alias Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.LiveHandler

  prop setting_boundaries, :boolean, default: false
  prop section, :any, default: nil
  prop parent_back, :any, default: nil
  prop scope, :any, default: nil

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
    scope = LiveHandler.scope_origin(assigns, socket)
    # |> IO.inspect
    %Paginator.Page{page_info: page_info, edges: edges} = LiveHandler.my_circles_paginated(scope)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       loaded: true,
       circles: edges,
       page_info: page_info,
       settings_section_title: "Create and manage your circles",
       settings_section_description: "Create and manage your circles."
     )}
  end

  # TODO
  def do_handle_event("back", _, socket) do
    {:noreply, assign(socket, :section, nil)}
  end

  def handle_event(
        action,
        attrs,
        socket
      ),
      do:
        Bonfire.UI.Common.LiveHandlers.handle_event(
          action,
          attrs,
          socket,
          __MODULE__,
          &do_handle_event/3
        )
end
