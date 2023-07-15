defmodule Bonfire.Boundaries.Web.BoundariesSelectionLive do
  use Bonfire.UI.Common.Web, :stateless_component

  # prop showing_within, :atom
  prop to_boundaries, :any, default: nil
  prop to_circles, :list, default: []
  prop exclude_circles, :list, default: []

  # def input_value(boundaries) do
  #   boundaries
  #   |> debug()
  #   |> Enum.map(fn {id, name} -> %{"value" => id, "text" => name} end)
  #   |> Jason.encode!()
  #   |> debug()

  #   # [{"value":"good", "text":"The Good, the Bad and the Ugly"}, {"value":"matrix", "text":"The Matrix"}]
  # end

  def presets(to_boundaries) do
    # [
    # {"public", l("Public")},
    # {"local", l("Local Instance")},
    # {"mentions", l("Mentions")}
    # ]
    # ++
    to_boundaries
    |> Enum.uniq()
    |> debug()
  end
end
