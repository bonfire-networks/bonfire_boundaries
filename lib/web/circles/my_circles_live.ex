defmodule Bonfire.Boundaries.Web.MyCirclesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  # import Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.LiveHandler

  prop setting_boundaries, :boolean, default: false
  prop section, :any, default: nil
  prop parent_back, :any, default: nil

  def update(assigns, socket) do
    circles = Bonfire.Boundaries.Circles.list_my_with_counts(current_user(assigns)) |> repo().maybe_preload(encircles: [subject: [:profile]]) #|> IO.inspect
    debug(circles, "Circles")

    {:ok, socket
      |> assign(assigns)
      |> assign(
      circles: circles,
      settings_section_title: "Create and manage your circles",
      settings_section_description: "Create and manage your circles."
      )}
  end

  def handle_event("back", _, socket) do # TODO
    {:noreply, socket
      |> assign(:section, nil)
    }
  end

  def handle_event(action, attrs, socket), do: Bonfire.UI.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)

end
