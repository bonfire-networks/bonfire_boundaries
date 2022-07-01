defmodule Bonfire.Boundaries.Web.ViewCircleLive do
  use Bonfire.UI.Common.Web, :stateful_component

  def update(assigns, socket) do
    # FIXME: what's the difference with EditCircleLive?

    id = e(assigns, :__context__, :current_params, "id", nil)
    |> debug

    with {:ok, circle} <- Bonfire.Boundaries.Circles.get_for_caretaker(id, current_user(assigns)) |> repo().maybe_preload(encircles: [subject: [:profile, :character]]) do
      debug(circle, "circle")

      member_ids = Enum.map(circle.encircles, & &1.subject_id)
      |> debug

      # TODO: handle pagination
      followed = Bonfire.Social.Follows.list_my_followed(current_user(assigns), paginate: false, exclude_ids: member_ids)

      already_seen_ids = member_ids ++ Enum.map(followed, & &1.edge.object_id)

      # |> debug
      followers = Bonfire.Social.Follows.list_my_followers(current_user(assigns), paginate: false, exclude_ids: already_seen_ids)
      # |> debug

      {:ok, socket
      |> assign(assigns)
      |> assign(
        circle: circle,
        followers: followers,
        followed:  followed,
        read_only: e(circle, :stereotyped, :stereotype_id, nil) in ["7DAPE0P1E1PERM1TT0F0110WME", "4THEPE0P1ES1CH00SET0F0110W"],
        settings_section_title: "View " <> e(circle, :named, :name, "Circle name") <> " circle",
        settings_section_description: l "Create and manage your circle."
      )}
    end
  end

  def handle_event(action, attrs, socket), do: Bonfire.UI.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)

end
