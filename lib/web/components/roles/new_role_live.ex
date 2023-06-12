defmodule Bonfire.Boundaries.Web.NewRoleLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop setting_boundaries, :boolean, default: false
  prop label, :string, default: nil
  prop parent_back, :any, default: nil
  prop scope, :any, default: nil
end
