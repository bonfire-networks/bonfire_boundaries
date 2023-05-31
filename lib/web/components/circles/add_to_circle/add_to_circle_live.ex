defmodule Bonfire.Boundaries.Web.AddToCircleLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Circles

  prop circles, :list, default: []
  prop user_id, :any, default: nil



  def handle_event("add", %{"id" => id, "circle" => circle}, socket) do
    with {:ok, _} <- Circles.add_to_circles(id, circle) do

     {:noreply,
       socket
       |> assign_flash(:info, l("Added to circle!"))}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not add to circle"))}

      end
  end

  def handle_event("remove", %{"id" => id, "circle" => circle}, socket) do
    with {1, _} <- Circles.remove_from_circles(id, circle) do
      {:noreply,
       socket
       |> assign_flash(:info, l("removed from circle!"))}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not remove to circle"))}

      end
  end

  def update(assigns, socket) do
    current_user = current_user(assigns)

    circles =
      Bonfire.Boundaries.Circles.list_my_with_counts(current_user, exclude_stereotypes: true)
      |> repo().maybe_preload(encircles: [subject: [:profile]])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       circles: circles,

     )}
  end


end
