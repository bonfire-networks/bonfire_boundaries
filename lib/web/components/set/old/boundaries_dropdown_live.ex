defmodule Bonfire.Boundaries.Web.BoundariesDropdownLive do
  use Bonfire.UI.Common.Web, :stateless_component

  # prop showing_within, :any
  prop to_boundaries, :list, default: []
  prop to_circles, :list, default: []
  prop thread_mode, :atom, default: nil
  prop showing_within, :any, default: nil
  prop create_object_type, :any, default: nil
end
