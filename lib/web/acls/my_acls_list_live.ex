defmodule Bonfire.Boundaries.Web.MyAclsListLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Web.AclLive
  alias Bonfire.Boundaries.Integration

  prop hide_breakdown, :boolean, default: false
  prop setting_boundaries, :boolean, default: false
  prop click_override, :boolean, default: false
  prop select_event, :string, default: nil
  prop to_boundaries, :list, default: []
  prop to_boundaries_ids, :list, default: []
  prop section, :any, default: nil

  def update(assigns, %{assigns: %{loaded: true}} = socket) do

    {:ok, socket
      |> assign(assigns)
    }
  end

  def update(assigns, socket) do
    built_in_ids = Acls.built_in_ids()

    opts = if e(assigns, :setting_boundaries, nil) do
      Acls.opts_for_dropdown()
    else
      extra_ids_to_include = if Integration.is_admin?(current_user(assigns)), do: built_in_ids, else: []

      [extra_ids_to_include: extra_ids_to_include]
    end


    acls = Acls.list_my_with_counts(current_user(assigns), opts)

    acls = if e(assigns, :hide_breakdown, nil), do: acls, else: acls |> repo().maybe_preload(grants: [:verb, subject: [:named, :profile, encircle_subjects: [:profile], stereotyped: [:named]]])
    debug(acls, "Acls")

    # acls |> Ecto.assoc(:grants) |> repo().aggregate(:count, :id)
    # |> debug("counts")

    {:ok, socket
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

  def handle_event("boundary_edit", %{"id"=> id}, socket) do
    debug(id, "boundary_edit")
    {:noreply, socket
      |> assign(:edit_acl_id, id)
    }
  end

  def handle_event("back", _, socket) do # TODO
    {:noreply, socket
      |> assign(:edit_acl_id, nil)
    }
  end

  def handle_event(action, attrs, socket), do: Bonfire.UI.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)

end
