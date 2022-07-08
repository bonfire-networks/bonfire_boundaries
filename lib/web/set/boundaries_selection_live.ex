defmodule Bonfire.Boundaries.Web.BoundariesSelectionLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop activity_type_or_reply, :any
  prop to_boundaries, :list
  prop to_circles, :list
  prop thread_mode, :string

end
