defmodule Bonfire.Boundaries.Web.BlockMenuButtonsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop object, :any, default: nil
  prop peered, :any, default: nil

  def peered(object, peered) do
    peered || e(object, :peered, nil) || e(object, :character, :peered, nil)
  end

  def handle_event(action, attrs, socket), do: Bonfire.UI.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)

end
