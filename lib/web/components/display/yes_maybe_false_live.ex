defmodule Bonfire.Boundaries.Web.YesMaybeFalseLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop id, :any, default: nil
  prop field_name, :any, default: nil

  prop value, :any, default: nil
  prop read_only, :boolean, default: false
  prop event_target, :any, default: nil
end
