defmodule Bonfire.Boundaries.Web.NewRoleButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component
  # alias Bonfire.Boundaries.Circles

  prop scope, :atom, default: nil
  prop setting_boundaries, :boolean, default: false
end
