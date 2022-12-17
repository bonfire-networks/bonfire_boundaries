defmodule Bonfire.Boundaries.Web.RolesDropdownLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop circle_id, :string, default: nil
  prop role, :any, default: nil
  prop extra_roles, :list, default: []
end
