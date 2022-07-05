defmodule Bonfire.Boundaries.Web.MyAclsLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Web.AclLive
  # import Bonfire.Boundaries.Integration

  def update(assigns, socket) do
    built_in_ids = Bonfire.Boundaries.Acls.built_in_ids
    # extra_ids_to_include = if is_admin?(current_user(assigns)), do: built_in_ids, else: []
    acls = Bonfire.Boundaries.Acls.list_my_with_counts(current_user(assigns), extra_ids_to_include: built_in_ids) |> repo().maybe_preload(grants: [:verb, subject: [:named, :profile, encircle_subjects: [:profile], stereotyped: [:named]]])
    debug(acls, "Acls")

    # acls |> Ecto.assoc(:grants) |> repo().aggregate(:count, :id)
    # |> debug("counts")

    {:ok, assign(socket,
    %{
      acls: acls,
      # built_ins: Bonfire.Boundaries.Acls.list_built_ins,
      built_in_ids: built_in_ids,
      settings_section_title: "Create and manage your boundaries",
      settings_section_description: "Create and manage your boundaries."
      })}
  end

  def handle_event(action, attrs, socket), do: Bonfire.UI.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)

end
