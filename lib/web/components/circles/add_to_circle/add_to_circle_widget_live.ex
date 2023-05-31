defmodule Bonfire.Boundaries.Web.AddToCircleWidgetLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Circles

  prop circles, :list, default: []
  prop user_id, :any, default: nil

  def do_handle_event("add", %{"id" => id, "circle" => circle}, socket) do
    # TODO: check permission
    # current_user = current_user(socket)
    with {:ok, _} <- Circles.add_to_circles(id, circle) do
      {:noreply,
       socket
       |> update(:circles, &Circles.preload_encircled_by(id, &1, force: true))
       |> assign_flash(:info, l("Added to circle!"))}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not add to circle"))}
    end
  end

  def do_handle_event("remove", %{"id" => id, "circle" => circle}, socket) do
    # TODO: check permission
    # current_user = current_user(socket)
    with {1, _} <- Circles.remove_from_circles(id, circle) do
      {:noreply,
       socket
       |> update(:circles, &Circles.preload_encircled_by(id, &1, force: true))
       |> assign_flash(:info, l("removed from circle!"))}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not remove to circle"))}
    end
  end

  def update(%{circles: circles_passed_down} = assigns, socket) when circles_passed_down != [] do
    debug("use circles passed down by parent component")
    # current_user = current_user(assigns) || current_user(socket)

    circles_passed_down =
      Circles.preload_encircled_by(e(assigns, :user_id, nil), circles_passed_down)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(circles: circles_passed_down)}
  end

  def update(assigns, %{assigns: %{circles: circles_already_loaded}} = socket)
      when circles_already_loaded != [] do
    debug("use circles already loaded (but reload membership)")
    # current_user = current_user(assigns) || current_user(socket)

    circles_already_loaded =
      Circles.preload_encircled_by(e(assigns, :user_id, nil), circles_already_loaded, force: true)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(circles: circles_already_loaded)}
  end

  def update(assigns, socket) do
    debug("initial load of circles")
    current_user = current_user(assigns) || current_user(socket)

    circles =
      Bonfire.Boundaries.Circles.list_my_with_counts(current_user, exclude_stereotypes: true)
      |> Circles.preload_encircled_by(e(assigns, :user_id, nil), ...)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(circles: circles)}
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
