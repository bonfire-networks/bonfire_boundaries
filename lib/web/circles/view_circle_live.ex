defmodule Bonfire.Boundaries.Web.ViewCircleLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Circles

  def update(assigns, %{assigns: %{loaded: true}} = socket) do
    params = e(assigns, :__context__, :current_params, %{})

    {:ok, socket
      |> assign(assigns)
      |> assign(
        section: e(params, "section", "members")
      )
    }
  end

  def update(assigns, socket) do
    # FIXME: what's the difference with EditCircleLive?

    params = e(assigns, :__context__, :current_params, %{})
    id = e(params, "id", nil)
    # |> debug

    with {:ok, circle} <- Circles.get_for_caretaker(id, current_user(assigns)) |> repo().maybe_preload(encircles: [subject: [:profile, :character]]) do
      debug(circle, "circle")

      members =  Enum.map(e(circle, :encircles, []), &(
        {&1.subject_id, &1}
      ))
      |> Map.new()
      # |> debug

      member_ids = Map.keys(members)
      # |> debug

      # TODO: handle pagination
      followed = Bonfire.Social.Follows.list_my_followed(current_user(assigns), paginate: false, exclude_ids: member_ids)

      already_seen_ids = member_ids ++ Enum.map(followed, & &1.edge.object_id)

      # |> debug
      followers = Bonfire.Social.Follows.list_my_followers(current_user(assigns), paginate: false, exclude_ids: already_seen_ids)
      # |> debug

      suggestions = Enum.map(followers ++ followed, fn follow ->
        u = f(follow)
        {u.id, u}
      end)
      |> Map.new()
      |> debug

      {:ok, socket
      |> assign(assigns)
      |> assign(
        loaded: true,
        section: e(params, "section", "members"),
        circle: circle |> Map.drop([:encircles]),
        members: members,
        suggestions: suggestions,
        read_only: e(circle, :stereotyped, :stereotype_id, nil) in ["7DAPE0P1E1PERM1TT0F0110WME", "4THEPE0P1ES1CH00SET0F0110W"],
        settings_section_title: "View " <> e(circle, :named, :name, "Circle name") <> " circle",
        settings_section_description: l "Create and manage your circle."
      )}
    end
  end

  def handle_event("add", attrs, socket) do
    # debug(attrs)
    with id when is_binary(id) <- e(attrs, "subject", nil),
         {:ok, _} <- Circles.add_to_circles(id, e(socket.assigns, :circle, nil)) do
      {:noreply, socket
        |> assign_flash(:info, l "Added to circle!")
        |> assign(
          members: Map.merge(%{id=> e(socket.assigns, :suggestions, %{})[id]}, e(socket.assigns, :members, %{})) |> debug
        )
      }
    else other ->
      error(other)
      {:noreply, socket
        |> assign_flash(:error, "Could not add to circle")
      }
    end
  end

  def handle_event("remove", attrs, socket) do
    # debug(attrs)
    with id when is_binary(id) <- e(attrs, "subject", nil),
         {1, _} <- Circles.remove_from_circles(id, e(socket.assigns, :circle, nil)) do
      {:noreply, socket
        |> assign_flash(:info, l "Removed from circle!")
        |> assign(
          members: Map.drop(e(socket.assigns, :members, nil), [id])
        )
      }
    else other ->
      error(other)
      {:noreply, socket
        |> assign_flash(:error, "Could not remove from circle")
      }
    end
  end

  def handle_event(action, attrs, socket), do: Bonfire.UI.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)

  def f(%{edge: %{object: %{profile: _} = user}}), do: user
  def f(%{edge: %{subject: %{profile: _} = user}}), do: user
  def f(user), do: user

end
