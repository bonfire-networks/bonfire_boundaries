defmodule Bonfire.Boundaries.Web.NewAclButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop setting_boundaries, :boolean, default: false
end
