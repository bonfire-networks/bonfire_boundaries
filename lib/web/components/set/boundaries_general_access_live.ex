defmodule Bonfire.Boundaries.Web.BoundariesGeneralAccessLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop preset_boundary, :any, default: nil
  prop to_boundaries, :any, default: nil
end
