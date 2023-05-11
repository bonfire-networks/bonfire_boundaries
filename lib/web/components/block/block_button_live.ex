defmodule Bonfire.Boundaries.Web.BlockButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component
  # TODO: make stateful and preload block status?

  prop object, :any
  prop parent_id, :string, default: nil
  prop with_icon, :boolean, default: false
  prop icon_class, :css_class, default: nil
  prop hide_text, :boolean, default: false
  prop my_block, :any
  prop type, :string, default: nil
  prop class, :css_class
  prop label, :string, default: nil
  prop only_admin, :boolean, default: false
  prop only_user, :boolean, default: false
  prop open_btn_label, :string, default: nil
  prop title, :string, default: nil
  # only used for unblock
  prop scope, :any
  # only used for unblock
  prop block_type, :any
end
