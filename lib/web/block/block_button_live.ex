defmodule Bonfire.Boundaries.Web.BlockButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component
  # TODO: make stateful and preload block status?

  prop object, :any
  prop my_block, :any
  prop class, :string
  prop label, :string
  prop scope, :any # only used for unblock
  prop block_type, :any # only used for unblock

  def handle_event(action, attrs, socket), do: Bonfire.UI.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)

end
