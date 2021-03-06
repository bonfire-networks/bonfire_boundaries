defmodule Bonfire.Boundaries.Web.BoundaryIconLive do
  use Bonfire.UI.Common.Web, :stateful_component

  prop object, :any
  prop object_boundary, :any, default: nil
  prop preload_boundary_name, :boolean, default: true

  def preload(list_of_assigns), do: Bonfire.Boundaries.LiveHandler.maybe_preload_boundaries(list_of_assigns, __MODULE__)

  def handle_event(action, attrs, socket), do: Bonfire.UI.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)

end
