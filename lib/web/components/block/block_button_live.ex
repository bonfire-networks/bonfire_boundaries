defmodule Bonfire.Boundaries.Web.BlockButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component
  import Bonfire.Boundaries.Integration

  # TODO: make stateful and preload block status?

  prop object, :any
  prop is_local_user, :any, default: nil

  prop scope, :any, default: nil
  prop type, :atom, default: :block
  prop my_block, :any, default: nil

  prop only_admin, :boolean, default: false
  prop only_user, :boolean, default: false

  # visual
  prop parent_id, :string, default: nil
  prop with_icon, :boolean, default: false
  prop icon_class, :css_class, default: nil
  prop hide_text, :boolean, default: false
  prop class, :css_class
  prop label, :string, default: nil
  prop open_btn_label, :string, default: nil
  prop title, :string, default: nil

  def render(assigns) do
    assigns
    |> assign_new(:type_display, fn ->
      case assigns[:type] do
        :block -> l("Block")
        :silence -> l("Silence")
        :ghost -> l("Ghost")
        :hide -> l("Hide")
        type -> type
      end
    end)
    |> assign(
      :can_instance_wide?,
      Bonfire.Boundaries.can?(assigns[:__context__], :block, :instance_wide)
    )
    |> render_sface()
  end
end
