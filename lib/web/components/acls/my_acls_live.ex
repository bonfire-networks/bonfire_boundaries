defmodule Bonfire.Boundaries.Web.MyAclsLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Acls
  # alias Bonfire.Boundaries.Verbs
  alias Bonfire.Boundaries.Web.AclLive
  alias Bonfire.Boundaries.Integration

  prop hide_breakdown, :boolean, default: false
  prop setting_boundaries, :boolean, default: false
  prop click_override, :boolean, default: false
  prop to_boundaries, :any, default: nil
  prop to_boundaries_ids, :list, default: []
  prop built_ins, :list, default: []
  prop section, :any, default: nil
  prop edit_acl_id, :string, default: nil
  prop scope, :any, default: :user

  def update(
        %{scope: scope} = assigns,
        %{assigns: %{loaded: true, scope: existing_scope}} = socket
      )
      when scope == existing_scope do
    debug("update1")

    {:ok,
     assign(
       socket,
       assigns
     )}
  end

  def update(assigns, socket) do
    debug("update2")
    current_user = current_user(assigns)
    built_in_ids = Acls.built_in_ids()
    scope = e(assigns, :scope, nil) || e(socket.assigns, :scope, nil)

    args =
      if e(assigns, :setting_boundaries, nil) do
        [current_user, Acls.opts_for_dropdown()]
      else
        if scope == :instance and
             (Integration.is_admin?(current_user) ||
                Bonfire.Boundaries.can?(current_user, :grant, :instance)) do
          [
            Bonfire.Boundaries.Fixtures.admin_circle(),
            [extra_ids_to_include: built_in_ids]
          ]
        else
          [current_user, Acls.opts_for_list()]
        end
      end

    acls = Acls.list_my_with_counts(List.first(args), Enum.at(args, 1))

    acls =
      if e(assigns, :hide_breakdown, nil),
        do: acls,
        else:
          repo().maybe_preload(
            acls,
            grants: [
              :verb,
              subject: [
                :named,
                :profile,
                encircle_subjects: [:profile],
                stereotyped: [:named]
              ]
            ]
          )

    debug(acls, "Acls")

    # acls |> Ecto.assoc(:grants) |> repo().aggregate(:count, :id)
    # |> debug("counts")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       loaded: true,
       acls: acls,
       # built_ins: Bonfire.Boundaries.Acls.list_built_ins,
       built_in_ids: built_in_ids,
       settings_section_title: "Create and manage your boundaries",
       settings_section_description: "Create and manage your boundaries."
     )}
  end

  def do_handle_event("boundary_edit", %{"id" => id}, socket) do
    debug(id, "boundary_edit")

    {:noreply, assign(socket, :edit_acl_id, id)}
  end

  # TODO
  def do_handle_event("back", _, socket) do
    {:noreply,
     socket
     |> assign(:edit_acl_id, nil)
     |> assign(:section, nil)}
  end

  def handle_event(
        action,
        attrs,
        socket
      ),
      do:
        Bonfire.UI.Common.LiveHandlers.handle_event(
          action,
          attrs,
          socket,
          __MODULE__,
          &do_handle_event/3
        )
end
