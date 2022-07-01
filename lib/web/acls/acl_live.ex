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
            new_grant = %{grant.verb_id => Map.drop(grant, [:subject])}
            Map.update(existing_map, :grants, new_grant, fn existing_grants ->
              Map.merge(existing_grants, new_grant)
            end)
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

      suggestions = (for user <- followed ++ followers do
        {e(user, :edge, :object, :id, nil), e(user, :edge, :object, :profile, :name, "")<>" - "<>Bonfire.Me.Characters.display_username(e(user, :edge, :object, nil))}
      end
      ++
      for circle <- circles do
        {e(circle, :id, nil), (e(circle, :named, :name, nil) || e(circle, :stereotyped, :named, :name, nil) || l "Untitled")<>" "<> l "(circle)" }
      end)
      |> Map.new
      |> debug

      {:ok, socket
      |> assign(assigns)
      |> assign(
        verbs: Bonfire.Boundaries.Verbs.list(:db, :id),
        acl: acl,
        list: subjects,
        suggestions: suggestions,
        read_only: e(acl, :stereotyped, :stereotype_id, nil) in ["7DAPE0P1E1PERM1TT0F0110WME", "4THEPE0P1ES1CH00SET0F0110W"],
        settings_section_title: "View " <> e(acl, :named, :name, "acl name") <> " boundary",
        settings_section_description: l "Create and manage your boundary."
      )}
    end
  end

  def handle_event("add", attrs, socket) do
    debug(attrs)
    id = e(attrs, "add", nil)
    {:noreply, socket
    |> assign(
      list: Map.merge(e(socket.assigns, :list, %{}), %{id=> %{subject: %{name: e(socket.assigns, :suggestions, id, nil)}}}) |> debug
    )}
  end

  def handle_event(action, attrs, socket), do: Bonfire.UI.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)

end
