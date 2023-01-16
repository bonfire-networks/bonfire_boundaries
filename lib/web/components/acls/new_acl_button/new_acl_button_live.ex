defmodule Bonfire.Boundaries.Web.NewAclButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop scope, :atom, default: nil
  prop myself, :map, default: nil
  prop setting_boundaries, :boolean, default: false
end
