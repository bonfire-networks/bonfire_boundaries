defmodule Bonfire.Boundaries.Web.BoundariesGeneralAccessLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop preset_boundary, :any, default: nil
  prop to_boundaries, :any, default: nil

  def matches?({preset, _}, preset), do: true
  def matches?([{preset, _}], preset), do: true
  def matches?(_, _), do: false
end
