defmodule Bonfire.Boundaries.Web.EditAclButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Boundaries.Acls

  prop acl, :any, default: nil
  prop read_only, :boolean, default: false
  prop acl_id, :string, default: nil
end
