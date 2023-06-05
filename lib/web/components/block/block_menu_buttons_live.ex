defmodule Bonfire.Boundaries.Web.BlockMenuButtonsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop object, :any, default: nil
  prop parent_id, :string, default: nil
  prop peered, :any, default: nil
  prop open_btn_label, :string, default: nil
  prop scope, :any, default: nil

  def peered(object, peered) do
    peered || e(object, :peered, nil) || e(object, :character, :peered, nil)
  end
end
