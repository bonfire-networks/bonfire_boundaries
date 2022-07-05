defmodule Bonfire.Boundaries.Web.MyCirclesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  # import Bonfire.Boundaries.Integration

  def update(assigns, socket) do
    circles = Bonfire.Boundaries.Circles.list_my_with_counts(current_user(assigns)) |> repo().maybe_preload(encircles: [subject: [:profile]]) #|> IO.inspect
    debug(circles, "Circles")

    {:ok, assign(socket,
    %{
      circles: circles,
      settings_section_title: "Create and manage your circles",
      settings_section_description: "Create and manage your circles."
      })}
  end

  def handle_event(action, attrs, socket), do: Bonfire.UI.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)

end
