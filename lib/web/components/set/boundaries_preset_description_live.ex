defmodule Bonfire.Boundaries.Web.BoundariesPresetDescriptionLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop to_boundaries, :any, default: nil

  def clone_context(to_boundaries) do
    case to_boundaries do
      [{:clone_context, boundary_name}] -> boundary_name
      [{"clone_context", boundary_name}] -> boundary_name
      _ -> false
    end
  end
end
