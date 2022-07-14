defmodule Bonfire.Boundaries.Web.BoundariesSelectionLive do
  use Bonfire.UI.Common.Web, :stateful_component

  # prop showing_within, :any
  prop to_boundaries, :list, default: nil
  prop to_circles, :list
  prop thread_mode, :string


  def handle_event("tagify_remove", %{"remove" => subject} = _attrs, socket) do
    Bonfire.Boundaries.LiveHandler.remove_from_acl(subject, socket)
  end


  def handle_event("tagify_add", %{"add" => id} = _attrs, socket) do
    Bonfire.Boundaries.LiveHandler.add_to_acl(id, socket)
  end

end
