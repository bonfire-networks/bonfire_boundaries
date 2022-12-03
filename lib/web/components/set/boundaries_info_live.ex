defmodule Bonfire.Boundaries.Web.BoundariesInfoLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop to_boundaries, :any, default: nil
  prop activity_type_or_reply, :any
end
