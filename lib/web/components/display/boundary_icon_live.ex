defmodule Bonfire.Boundaries.Web.BoundaryIconLive do
  use Bonfire.UI.Common.Web, :stateful_component

  # Tip: use this component if you want to auto-preload boundaries (async), otherwise use `BoundaryIconStatelessLive` if a parent component can provide the `object_boundary` data

  prop object, :any, required: true

  # can also provide it manually
  prop object_boundary, :any, default: nil
  prop preset_boundary, :any, default: nil

  prop scope, :any, default: nil

  prop with_icon, :boolean, default: false
  prop with_label, :boolean, default: false

  prop class, :css_class, default: nil

  def preload(list_of_assigns),
    do:
      Bonfire.Boundaries.LiveHandler.preload(list_of_assigns,
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
