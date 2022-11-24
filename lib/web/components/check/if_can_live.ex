defmodule Bonfire.Boundaries.Web.IfCan do
  use Bonfire.UI.Common.Web, :stateful_component

  # WIP - need to find a way to check different verbs for each instance of this component in an efficient way

  prop object, :any
  prop verbs, :any, default: nil
  prop if_not_say, :string, default: nil

  # internal use only:
  prop boundary_can, :boolean, default: false
  prop check_object_boundary, :boolean, default: true

  slot default
  slot if_not

  def preload(list_of_assigns),
    do:
      Bonfire.Boundaries.LiveHandler.maybe_check_boundaries(list_of_assigns,
        caller_module: __MODULE__
      )

  def handle_event(
        action,
        attrs,
        socket
      ),
      do:
        Bonfire.UI.Common.LiveHandlers.handle_event(
          action,
          attrs,
          socket,
          __MODULE__
          # &do_handle_event/3
        )
end
