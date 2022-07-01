defmodule Bonfire.Boundaries.Web.AclLive do
  use Bonfire.UI.Common.Web, :stateful_component

  def update(assigns, socket) do
    current_user = current_user(assigns)

    # FIXME: what's the difference with EditAclLive?

    id = e(assigns, :__context__, :current_params, "id", nil)
    |> debug

    with {:ok, acl} <- Bonfire.Boundaries.Acls.get_for_caretaker(id, current_user) |> repo().maybe_preload(grants: [:verb, :subject]) do
      debug(acl, "acl")

      subjects = Enum.reduce(e(acl, :grants, []), %{}, fn grant, acc ->
        Map.update(acc,
          grant.subject_id,
          %{subject: grant.subject |> repo().maybe_preload([:named, :profile, :character, stereotyped: [:named]])},
          fn existing_map ->
            new_grant = [Map.drop(grant, [:subject])]
            Map.update(existing_map, :grants, new_grant, fn existing_grants -> existing_grants ++ new_grant end)
        end)
      end)
      # |> Map.new()
      |> debug

      already_set_ids = Map.keys(subjects)

      # # TODO: handle pagination?
      followed = Bonfire.Social.Follows.list_my_followed(current_user, paginate: false, exclude_ids: already_set_ids)

      already_seen_ids = already_set_ids ++ Enum.map(followed, & &1.edge.object_id)
      # # |> debug
      followers = Bonfire.Social.Follows.list_my_followers(current_user, paginate: false, exclude_ids: already_seen_ids)
      # |> debug

      circles = Bonfire.Boundaries.Circles.list_my(current_user)

      {:ok, socket
      |> assign(assigns)
      |> assign(
        acl: acl,
        list: subjects,
        users: followed ++ followers,
        user_circles: circles,
        read_only: e(acl, :stereotyped, :stereotype_id, nil) in ["7DAPE0P1E1PERM1TT0F0110WME", "4THEPE0P1ES1CH00SET0F0110W"],
        settings_section_title: "View " <> e(acl, :named, :name, "acl name") <> " boundary",
        settings_section_description: l "Create and manage your boundary."
      )}
    end
  end

  def handle_event("add", attrs, socket) do
    debug(attrs)
    {:noreply, socket
    |> assign(
      list: e(socket.assigns, :list, []) ++ [%{e(attrs, "to_circles", nil)=> nil}]
    )}
  end

  def handle_event(action, attrs, socket), do: Bonfire.UI.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)

end
