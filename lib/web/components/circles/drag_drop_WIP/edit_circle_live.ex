defmodule Bonfire.Boundaries.Web.EditCircleLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Circles

  def update(assigns, socket) do
    # FIXME: what's the difference with EditCircleLive?

    id = e(assigns, :__context__, :current_params, "id", nil)

    # |> debug()

    with {:ok, circle} <-
           Circles.get_for_caretaker(
             id,
             current_user(assigns) || current_user(assigns(socket))
           )
           |> repo().maybe_preload(encircles: [subject: [:profile, :character]]) do
      debug(circle, "circle")

      member_ids =
        Enum.map(circle.encircles, & &1.subject_id)
        |> debug()

      # TODO: handle pagination
      followed =
        Bonfire.Social.Graph.Follows.list_my_followed(current_user_required!(assigns),
          paginate: false,
          exclude_ids: member_ids
        )

      already_seen_ids = member_ids ++ Enum.map(followed, & &1.edge.object_id)

      # |> debug
      followers =
        Bonfire.Social.Graph.Follows.list_my_followers(current_user_required!(assigns),
          paginate: false,
          exclude_ids: already_seen_ids
        )

      # |> debug

      follow_stereotypes = Circles.stereotypes(:follow)

      {:ok,
       socket
       |> assign(assigns)
       |> assign(
         circle: circle,
         followers: followers,
         followed: followed,
         read_only:
           e(circle, :stereotyped, :stereotype_id, nil) in follow_stereotypes or
             uid(circle) in follow_stereotypes,
         settings_section_title: "View " <> e(circle, :named, :name, "Circle name") <> " circle",
         settings_section_description: l("Create and manage your circle.")
       )}
    end
  end
end
