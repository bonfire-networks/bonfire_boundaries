defmodule Bonfire.Boundaries.Web.BoundaryItemsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop to_boundaries, :any, default: nil
  prop circles, :any, default: []
  prop roles_for_dropdown, :any, default: nil
end
