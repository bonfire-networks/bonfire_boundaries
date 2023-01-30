defmodule Bonfire.Boundaries.Web.BlockButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component
  # TODO: make stateful and preload block status?

  prop object, :any
  prop with_icon, :boolean, default: false
  prop my_block, :any
  prop class, :css_class
  prop label, :string, default: nil
  prop open_btn_label, :string, default: nil
  # only used for unblock
  prop scope, :any
  # only used for unblock
  prop block_type, :any
end
