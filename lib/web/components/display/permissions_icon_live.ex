defmodule Bonfire.Boundaries.Web.PermissionsIconLive do
  use Bonfire.UI.Common.Web, :stateless_component

  # Tip: use `BoundaryIconLive` unless you don't want to preload boundaries, and instead a parent component is providing the `object_boundary` data
  prop object_boundary, :any, default: nil
  prop boundary_tuple, :any, default: nil

  prop with_icon, :boolean, default: false
  prop with_label, :boolean, default: false

  prop class, :css_class, default: "text-sm text-neutral-content/80 border-b border-neutral-content/5 bg-base-content/5"
end
