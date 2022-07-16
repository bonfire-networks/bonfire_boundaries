defmodule Bonfire.Boundaries.Web.NewCircleLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop event_target, :any
  prop setting_boundaries, :boolean, default: false
  prop label, :string, default: nil

end
