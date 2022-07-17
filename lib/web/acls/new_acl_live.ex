defmodule Bonfire.Boundaries.Web.NewAclLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop event_target, :any, default: nil
  prop setting_boundaries, :boolean, default: false
  prop label, :string, default: nil
  prop parent_back, :any, default: nil

end
