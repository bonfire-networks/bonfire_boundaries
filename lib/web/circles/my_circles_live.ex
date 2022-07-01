defmodule Bonfire.Boundaries.Web.MyCirclesLive do
  use Bonfire.UI.Common.Web, :stateful_component

  def update(assigns, socket) do
    circles = Bonfire.Boundaries.Circles.list_my(current_user(assigns)) #|> IO.inspect
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
