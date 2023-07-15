defmodule Bonfire.Boundaries.Web.ExcludeBoundaries do
  use Bonfire.UI.Common
  alias Bonfire.Boundaries.Web.SetBoundariesLive

  def do_handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket) do
    SetBoundariesLive.live_select_change(live_select_id, search, :exclude_circles, socket)
  end

  def do_handle_event(
        event,
        params,
        socket
      ) do
    SetBoundariesLive.do_handle_event(
      event,
      params,
      socket
    )
  end
end
