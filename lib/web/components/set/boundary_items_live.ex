defmodule Bonfire.Boundaries.Web.BoundaryItemsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop to_boundaries, :any, default: nil
  prop to_circle, :any, default: nil
end
