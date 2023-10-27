defmodule Bonfire.Boundaries.Web.RoleLive do
  use Bonfire.UI.Common.Web, :stateful_component

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(page_title: l("Role"))}
  end
end
