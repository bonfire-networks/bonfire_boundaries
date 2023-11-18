defmodule Bonfire.Boundaries.Web.BoundaryDetailsLive do
  use Bonfire.UI.Common.Web, :stateless_component
  # TODO: make stateful?

  alias Bonfire.Boundaries.LiveHandler
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Roles

  # Tip: use `BoundaryIconLive` unless you don't want to preload boundaries, and instead a parent component is providing the `object_boundary` data
  prop object_id, :string, required: true
  prop object_boundary, :any, default: nil
  prop object_type, :any, default: nil
  prop boundary_preset, :any, default: nil
  prop scope, :any, default: nil
  prop phx_target, :any, default: nil

  prop to_circles, :list, default: []
  prop exclude_circles, :list, default: []

  prop presets_acls, :list, default: []
  prop custom_acls, :list, default: []

  def render(%{object_boundary: none} = assigns) when none in [nil, false] do
    assigns
    |> render_sface()
  end

  def render(assigns) do
    role = Roles.preset_boundary_role_from_acl(assigns[:object_boundary])

    role_name =
      case role do
        {role_name, _permissions} -> role_name
        _ -> nil
      end

    is_caretaker = role_name in ["Administer", "Caretaker"]

    assigns
    |> assign(
      role_name: role_name,
      is_caretaker: is_caretaker,
      role_permissions:
        case role do
          {_role, permissions} -> permissions
          _ -> nil
        end
    )
    |> assign(
      for_view_edit(
        is_caretaker,
        assigns[:object_id],
        assigns[:boundary_preset],
        assigns[:__context__]
      )
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

    {presets_acls, custom_acls} =
      object_acls
      |> Enum.split_with(&e(&1, :named, nil))

    # TODO ^ check that we're the caretaker of an ACL (or it's a preset) to include it in presets_acls

    to_boundaries =
      presets_acls
      #    |> Enum.reject(& id(&1) in global_preset_acl_ids)
      |> Enum.map(&{id(&1), e(&1, :named, :name, l("Unnamed preset boundary"))})

    # TODO: use boundary summary instead so we get the computed boundary?
    # NOTE: custom_acls will be editable within AclLive, so only use presets_acls here
    {to_circles, exclude_circles} =
      Acls.acl_grants_to_tuples(current_user_required!(context), presets_acls)
      |> Roles.split_tuples_can_cannot()

    [
      # boundary_preset: e(List.first(to_boundaries), boundary_preset),
      #  TODO: this seems unused by SetBoundariesLive, do we need to compute to_circles instead?
      to_boundaries: to_boundaries,
      presets_acls: presets_acls,
      custom_acls: e(custom_acls, nil) || init_object_custom_acl(object_id, context),
      to_circles: to_circles,
      exclude_circles: exclude_circles
    ]
    |> debug("view boundaries")
  end

  defp for_view_edit(_, _, boundary_preset, _), do: [boundary_preset: boundary_preset]

  defp init_object_custom_acl(object_id, context) do
    case Acls.get_or_create_object_custom_acl(object_id, current_user(context)) do
      {:ok, acl} ->
        [acl]

      e ->
        error(e)
        []
    end
  end
end
