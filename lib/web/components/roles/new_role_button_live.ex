defmodule Bonfire.Boundaries.Web.NewRoleButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component
  # alias Bonfire.Boundaries.Circles

  prop scope, :any, default: nil
  prop scope_type, :any, default: nil
  prop setting_boundaries, :boolean, default: false
  prop event_target, :any, default: nil
end
