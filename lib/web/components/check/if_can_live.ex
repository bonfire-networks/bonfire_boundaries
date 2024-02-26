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

  def update_many(assigns_sockets),
    do:
      Bonfire.Boundaries.LiveHandler.maybe_check_boundaries(assigns_sockets,
        caller_module: __MODULE__
      )
end
