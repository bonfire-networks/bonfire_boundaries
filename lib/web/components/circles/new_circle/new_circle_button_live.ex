defmodule Bonfire.Boundaries.Web.NewCircleButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Boundaries.Circles

  prop scope, :atom, default: nil
  prop myself, :map, default: nil
  prop setting_boundaries, :boolean, default: false
end
