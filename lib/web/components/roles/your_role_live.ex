defmodule Bonfire.Boundaries.Web.YourRoleLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop role_name, :string, required: true
  prop label, :string, default: nil
  prop role_permissions, :any, default: nil
  prop is_caretaker, :boolean, default: true
  prop scope, :any, default: nil
end
