defmodule Bonfire.Boundaries.Web.BoundariesPresetNameLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop to_boundaries, :any, default: nil
  prop preset_boundary, :any, default: nil

  prop class, :css_class, default: "flex items-center gap-1"
  prop icon_class, :css_class, default: "w-5 h-5 text-base-content/60"

  prop with_icon, :boolean, default: true
  prop with_label, :boolean, default: true
end
