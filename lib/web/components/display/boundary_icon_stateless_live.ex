defmodule Bonfire.Boundaries.Web.BoundaryIconStatelessLive do
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Roles

  # Tip: use `BoundaryIconLive` unless you don't want to preload boundaries, and instead a parent component is providing the `object_boundary` data
  prop object_id, :string, required: true
  prop parent_id, :string, default: nil
  prop object_boundary, :any, default: nil
  prop object_type, :any, default: nil
  prop boundary_preset, :any, default: nil
  prop scope, :any, default: nil

  prop with_icon, :boolean, default: true
  prop with_label, :boolean, default: false

  prop class, :css_class, default: nil

  def render(%{object_boundary: none} = assigns) when none in [nil, false] do
    assigns
    |> render_sface()
  end

  def render(assigns) do
    assigns
    |> update(:boundary_preset, fn existing ->
      (existing ||
         Bonfire.Boundaries.preset_boundary_tuple_from_acl(
           assigns[:object_boundary],
           e(assigns, :object_type, nil)
         ) ||
         {"custom", l("Custom")})
      |> debug("boundary_preset")
    end)
    |> assign(modal_id: "icon_modal_#{assigns[:parent_id] || "boundary_#{assigns[:object_id]}"}")
    |> render_sface()
  end
end
