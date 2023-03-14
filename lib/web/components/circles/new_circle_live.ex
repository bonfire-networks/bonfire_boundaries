defmodule Bonfire.Boundaries.Web.NewCircleLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop setting_boundaries, :boolean, default: false
  prop event_target, :any, default: %{}
end
