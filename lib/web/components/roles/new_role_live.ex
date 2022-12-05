defmodule Bonfire.Boundaries.Web.NewRoleLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop event_target, :any
  prop setting_boundaries, :boolean, default: false
  prop label, :string, default: nil
  prop parent_back, :any, default: nil
  prop scope, :atom, default: nil
end
