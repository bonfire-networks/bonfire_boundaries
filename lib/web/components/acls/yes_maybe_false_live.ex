defmodule Bonfire.Boundaries.Web.YesMaybeFalseLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop value, :any, default: nil
  prop read_only, :boolean, default: false
  prop field_name, :any, default: nil
  prop event_target, :any, default: nil
end
