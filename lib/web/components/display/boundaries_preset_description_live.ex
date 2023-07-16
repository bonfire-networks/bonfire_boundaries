defmodule Bonfire.Boundaries.Web.BoundariesPresetDescriptionLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop to_boundaries, :any, default: nil
  prop preset_boundary, :any, default: nil
  prop with_icon, :boolean, default: false
end
