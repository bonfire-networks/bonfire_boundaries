defmodule Bonfire.Boundaries.Web.BoundariesPresetNameLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop to_boundaries, :any, default: nil
  prop boundary_preset, :any, default: nil

  prop class, :css_class, default: ""
  prop icon_class, :css_class, default: "w-5 h-5 text-base-content/60"
  prop icon_wrapper, :css_class, default: ""
  prop with_icon, :boolean, default: true
  prop with_label, :boolean, default: true
  prop with_description, :boolean, default: false
end
