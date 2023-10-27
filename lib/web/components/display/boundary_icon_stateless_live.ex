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
    object_boundary =
      assigns[:object_boundary]
      |> debug("object_boundary")

    role = Roles.preset_boundary_role_from_acl(object_boundary)

    role_name =
      case role do
        {role_name, _permissions} -> role_name
        _ -> nil
      end

    is_caretaker = role_name in ["Administer", "Caretaker"]

    debug(e(assigns, :object_type, nil))

    assigns
    |> update(:boundary_preset, fn existing ->
      (existing ||
         Bonfire.Boundaries.preset_boundary_tuple_from_acl(
           object_boundary,
           e(assigns, :object_type, nil)
         ) ||
         {"custom", l("Custom")})
      |> debug("boundary_preset")
    end)
    |> assign(
      role_name: role_name,
      is_caretaker: is_caretaker
    )
    |> assign(
      :role_permissions,
      case role do
        {_role, permissions} -> permissions
        _ -> nil
      end
    )
    |> render_sface()
  end

  defp for_view_edit(true, object_id, boundary_preset, context) when is_binary(object_id) do
    # for caretaker
    # global_preset_acl_ids = Bonfire.Boundaries.Acls.preset_acl_ids()

    # TODO: query only custom per-object ACL (stereotype 7HECVST0MAC1F0RAN0BJECTETC) instead?
    # , exclude_ids: global_preset_acl_ids
    object_acls =
      Bonfire.Boundaries.list_object_boundaries(object_id)
      |> debug("acls_to_boundaries")

    {my_presets, custom_acls} =
      object_acls
      |> Enum.split_with(&e(&1, :named, nil))

    # TODO ^ check that we're the caretaker of an ACL (or it's a preset) to include it in my_presets

    my_presets =
      my_presets
      #    |> Enum.reject(& id(&1) in global_preset_acl_ids)
      |> Enum.map(&{id(&1), e(&1, :named, :name, l("Unnamed preset boundary"))})

    {to_circles, exclude_circles} =
      Acls.acl_grants_to_tuples(current_user_required!(context), object_acls)
      |> Roles.split_tuples_can_cannot()

    [
      boundary_preset: e(List.first(my_presets), boundary_preset),
      #  TODO: this seems unused by SetBoundariesLive, do we need to compute to_circles instead?
      to_boundaries: my_presets,
      custom_acls: custom_acls,
      to_circles: to_circles,
      exclude_circles: exclude_circles
    ]
    |> debug("view boundaries")
  end

  defp for_view_edit(_, _, boundary_preset, _), do: [boundary_preset: boundary_preset]
end
