defmodule Bonfire.Boundaries.Web.BoundariesDropdownLive do
  use Bonfire.UI.Common.Web, :stateless_component

  # prop showing_within, :any
  prop to_boundaries, :list, default: []
  prop to_circles, :list
  prop thread_mode, :string

end
