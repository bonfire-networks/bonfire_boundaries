defmodule Bonfire.Boundaries.Web.BlockMenuButtonsLive do
  use Bonfire.UI.Common.Web, :stateless_component
  import Bonfire.Boundaries.Integration

  prop object, :any, default: nil
   prop silence_extra_object, :any, default: nil
 prop parent_id, :string, default: nil
  prop peered, :any, default: nil
  prop open_btn_label, :string, default: nil
  prop extra_object_label, :string, default: nil
  prop scope, :any, default: nil

  def peered(object, peered) do
    (peered || e(object, :peered, nil) || e(object, :character, :peered, nil))
    |> debug()
  end
end
