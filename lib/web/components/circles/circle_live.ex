defmodule Bonfire.Boundaries.Web.CircleLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.LiveHandler

  @follow_stereotypes [
    "7DAPE0P1E1PERM1TT0F0110WME",
    "4THEPE0P1ES1CH00SET0F0110W"
  ]

  prop circle_id, :any, default: nil
  prop parent_back, :any, default: nil
  prop setting_boundaries, :boolean, default: false
  prop scope, :atom, default: nil
  prop showing_within, :atom, default: nil
  prop feedback_title, :string, default: nil
  prop feedback_message, :string, default: nil
  prop read_only, :boolean, default: false

  def update(assigns, %{assigns: %{loaded: true}} = socket) do
    params = e(assigns, :__context__, :current_params, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(page_title: l("Circle"))
     |> assign(section: e(params, "section", "members"))}
  end

  def update(assigns, socket) do
    current_user = current_user(assigns)

    params = e(assigns, :__context__, :current_params, %{})

    id =
      (e(assigns, :circle_id, nil) || e(params, "id", nil))
      |> debug()

    socket =
      socket
      |> assign(assigns)
      |> assign(
        loaded: true,
        page_title: l("Circle"),
        section: e(params, "section", "members"),
        settings_section_description: l("Create and manage your circle.")
      )

    with {:ok, circle} <-
           Circles.get_for_caretaker(id, current_user, scope: e(socket.assigns, :scope, nil))
           |> repo().maybe_preload(encircles: [subject: [:profile, :character]]) do
      debug(circle, "circle")

      members =
        Enum.map(e(circle, :encircles, []), &{&1.subject_id, &1})
        |> Map.new()
        |> debug("members")

      member_ids = Map.keys(members)
      # |> debug

      # TODO: handle pagination
      # followed =
      #   Bonfire.Social.Follows.list_my_followed(current_user,
      #     paginate: false,
      #     exclude_ids: member_ids
      #   )

      # already_seen_ids = member_ids ++ Enum.map(followed, & &1.edge.object_id)

      # # |> debug
      # followers =
      #   Bonfire.Social.Follows.list_my_followers(current_user,
      #     paginate: false,
      #     exclude_ids: already_seen_ids
      #   )

      # # |> debug

      # suggestions =
      #   Enum.map(followers ++ followed ++ [current_user], fn follow ->
      #     u = f(follow)
      #     {ulid(u), u}
      #   end)
      #   |> Map.new()
      #   |> debug

      stereotype_id = e(circle, :stereotyped, :stereotype_id, nil)

      send_self(
        page_title: e(circle, :named, :name, nil) || e(circle, :stereotyped, :named, :name, nil),
        back: true,
        circle: circle,
        page_header_aside: [
          {Bonfire.Boundaries.Web.HeaderCircleLive,
           [
             circle: circle,
             myself: e(socket, :myself, nil),
             stereotype_id: stereotype_id,
             #  suggestions: suggestions,
             read_only:
               e(socket.assigns, :read_only, nil) ||
                 e(circle, :stereotyped, :stereotype_id, nil) in @follow_stereotypes ||
                 ulid(circle) in @follow_stereotypes
           ]}
        ]
      )

      {:ok,
       assign(
         socket,
         circle: Map.drop(circle, [:encircles]),
         members: members,
         page_title: l("Circle"),
         #  suggestions: suggestions,
         stereotype_id: stereotype_id,
         read_only:
           stereotype_id in @follow_stereotypes or
             ulid(circle) in @follow_stereotypes,
         settings_section_title: "View " <> e(circle, :named, :name, "") <> " circle"
       )}

      # else other ->
      #   error(other)
      #   {:ok, socket
      #     |> assign_flash(:error, l "Could not find circle")
      #     |> assign(
      #       circle: nil,
      #       members: [],
      #       suggestions: [],
      #       read_only: true
      #     )
      #     # |> redirect_to("/boundaries/circles")
      #   }
    end
  end

  def do_handle_event("multi_select", %{data: data, text: text}, socket) do
    add_member(data |> Enum.into(%{name: text}), socket)
  end

  def do_handle_event("select", %{"id" => id}, socket) do
    # debug(attrs)
    add_member(e(socket.assigns, :suggestions, %{})[id] || id, socket)
  end

  def do_handle_event(
        "remove",
        %{"subject" => id} = attrs,
        %{assigns: %{showing_within: showing_within}} = socket
      )
      when not is_nil(showing_within) and is_binary(id) do
    LiveHandler.unblock(id, showing_within, socket.assigns[:scope], socket)
  end

  def do_handle_event("remove", %{"subject" => id} = attrs, socket) when is_binary(id) do
    with {1, _} <-
           Circles.remove_from_circles(id, e(socket.assigns, :circle, nil)) do
      {:noreply,
       socket
       |> assign_flash(:info, l("Removed from circle!"))
       |> assign(members: Map.drop(e(socket.assigns, :members, nil), [id]))}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not remove from circle"))}
    end
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

  def handle_info(%LiveSelect.ChangeMsg{text: search} = change_msg, socket) do
    current_user = current_user(socket)

    Bonfire.Me.Users.search(search)
    |> Bonfire.Boundaries.Web.SetBoundariesLive.results_for_multiselect()
    |> LiveSelect.update_options(change_msg, ...)

    {:noreply, socket}
  end

  def add_member(subject, socket) do
    # debug(attrs)
    with id when is_binary(id) <- ulid(subject),
         {:ok, _} <- Circles.add_to_circles(id, e(socket.assigns, :circle, nil)) do
      {:noreply,
       socket
       |> assign_flash(:info, l("Added to circle!"))
       |> assign(
         members:
           Map.merge(
             %{id => subject},
             e(socket.assigns, :members, %{})
           )
           |> debug()
       )}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not add to circle"))}
    end
  end

  def f(%{edge: %{object: %{profile: _} = user}}), do: user
  def f(%{edge: %{subject: %{profile: _} = user}}), do: user
  def f(user), do: user
end
