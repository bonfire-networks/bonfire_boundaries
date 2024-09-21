defmodule Bonfire.Boundaries.Web.CircleLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Blocks

  prop circle_id, :any, default: nil
  prop circle, :any, default: nil
  prop circle_type, :atom, default: nil
  prop name, :string, default: nil
  prop parent_back, :any, default: nil
  prop setting_boundaries, :boolean, default: false
  prop scope, :any, default: nil
  prop showing_within, :atom, default: nil
  prop feedback_title, :string, default: nil
  prop feedback_message, :string, default: nil
  prop read_only, :boolean, default: false
  prop show_add, :boolean, default: nil
  prop show_remove, :boolean, default: nil

  slot default, required: false

  def update(assigns, %{assigns: %{loaded: true}} = socket) do
    params = e(assigns, :__context__, :current_params, %{})

    {:ok,
     socket
     |> assign(assigns)
     #  |> assign(page_title: l("Circle"))
     |> assign(section: e(params, "section", "members"))}
  end

  def update(assigns, socket) do
    current_user = current_user(assigns) || current_user(assigns(socket))

    # assigns
    # |> debug("assigns")

    params =
      e(assigns, :__context__, :current_params, %{})
      |> debug("current_params")

    id =
      (e(assigns, :circle_id, nil) || e(params, "id", nil))
      |> debug("circle_id")

    socket =
      socket
      |> assign(assigns)
      |> assign(
        loaded: true,
        # page_title: l("Circle"),
        section: e(params, "section", "members"),
        settings_section_description: l("Create and manage your circle.")
      )

    with %{id: id} = circle <-
           (e(assigns, :circle, nil) ||
              Circles.get_for_caretaker(id, current_user, scope: e(assigns(socket), :scope, nil)))
           |> repo().maybe_preload(encircles: [subject: [:profile, :character]])
           |> repo().maybe_preload(encircles: [subject: [:named]])
           |> ok_unwrap() do
      debug(circle, "circle")

      members =
        Enum.map(e(circle, :encircles, []), &{&1.subject_id, &1})
        |> Map.new()
        |> debug("members")

      # member_ids = Map.keys(members)
      # |> debug

      # TODO: handle pagination
      # followed =
      #   Bonfire.Social.Graph.Follows.list_my_followed(current_user,
      #     paginate: false,
      #     exclude_ids: member_ids
      #   )

      # already_seen_ids = member_ids ++ Enum.map(followed, & &1.edge.object_id)

      # # |> debug
      # followers =
      #   Bonfire.Social.Graph.Follows.list_my_followers(current_user,
      #     paginate: false,
      #     exclude_ids: already_seen_ids
      #   )

      # # |> debug

      # suggestions =
      #   Enum.map(followers ++ followed ++ [current_user], fn follow ->
      #     u = f(follow)
      #     {uid(u), u}
      #   end)
      #   |> Map.new()
      #   |> debug

      stereotype_id = e(circle, :stereotyped, :stereotype_id, nil)

      follow_stereotypes = Circles.stereotypes(:follow)

      read_only = e(assigns, :read_only, nil) || e(assigns(socket), :read_only, nil)

      read_only =
        if is_nil(read_only) do
          Circles.is_built_in?(circle) ||
            stereotype_id in follow_stereotypes
        else
          read_only
        end

      if socket_connected?(socket),
        do:
          send_self(
            read_only: read_only,
            page_title:
              e(circle, :named, :name, nil) || e(assigns(socket), :name, nil) ||
                e(circle, :stereotyped, :named, :name, nil) || l("Circle"),
            back: true,
            circle: circle
            # page_header_aside: [
            #   {Bonfire.Boundaries.Web.HeaderCircleLive,
            #    [
            #      circle: circle,
            #      stereotype_id: stereotype_id,
            #      #  suggestions: suggestions,
            #      read_only: read_only
            #    ]}
            # ]
          )

      {:ok,
       assign(
         socket,
         circle: Map.drop(circle, [:encircles]),
         members: members || %{},
         #  page_title: l("Circle"),
         #  suggestions: suggestions,
         stereotype_id: stereotype_id,
         read_only: read_only,
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

  def handle_event("multi_select", %{data: data, text: _text}, socket) do
    add_member(input_to_atoms(data), socket)
  end

  def handle_event("select", %{"id" => id}, socket) do
    # debug(attrs)
    add_member(input_to_atoms(e(assigns(socket), :suggestions, %{})[id]) || id, socket)
  end

  def handle_event(
        "remove",
        %{"subject" => id} = _attrs,
        %{assigns: %{scope: scope, circle_type: circle_type}} = socket
      )
      when is_binary(id) and circle_type in [:silence, :ghost] do
    with {:ok, _} <-
           Blocks.unblock(id, circle_type, scope || current_user(assigns(socket))) do
      {:noreply,
       socket
       |> update(:members, &Map.drop(&1, [id]))
       |> assign_flash(:info, l("Unblocked!"))}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not unblock"))}
    end
  end

  def handle_event("remove", %{"subject" => id} = _attrs, socket) when is_binary(id) do
    with {1, _} <-
           Circles.remove_from_circles(id, e(assigns(socket), :circle, nil)) do
      {:noreply,
       socket
       |> update(:members, &Map.drop(&1, [id]))
       |> assign_flash(:info, l("Removed from circle!"))}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not remove from circle"))}
    end
  end

  def handle_event(
        "live_select_change",
        %{"id" => live_select_id, "text" => search},
        %{assigns: %{circle_type: circle_type}} = socket
      )
      when circle_type in [:silence, :ghost] do
    current_user_id =
      current_user_id(socket)
      |> debug("avoid blocking myself")

    do_results_for_multiselect(search)
    |> Enum.reject(fn {_name, %{id: id}} -> id == current_user_id end)
    |> maybe_send_update(LiveSelect.Component, live_select_id, options: ...)

    {:noreply, socket}
  end

  def handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket) do
    debug(assigns(socket))

    do_results_for_multiselect(search)
    |> maybe_send_update(LiveSelect.Component, live_select_id, options: ...)

    {:noreply, socket}
  end

  def do_results_for_multiselect(search) do
    Bonfire.Common.Utils.maybe_apply(
      Bonfire.Me.Users,
      :search,
      [search]
    )
    |> Bonfire.Boundaries.Web.SetBoundariesLive.results_for_multiselect()
  end

  def add_member(subject, %{assigns: %{scope: scope, circle_type: circle_type}} = socket)
      when circle_type in [:silence, :ghost] do
    with id when is_binary(id) <- uid(subject),
         {:ok, _} <- Blocks.block(id, circle_type, scope || current_user(assigns(socket))) do
      {:noreply,
       socket
       |> assign_flash(:info, l("Blocked!"))
       |> assign(
         members:
           Map.merge(
             %{id => subject},
             e(assigns(socket), :members, %{})
           )
           |> debug()
       )}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not block"))}
    end
  end

  def add_member(subject, socket) do
    with id when is_binary(id) <- uid(subject),
         {:ok, _} <- Circles.add_to_circles(id, e(assigns(socket), :circle, nil)) do
      {:noreply,
       socket
       |> assign_flash(:info, l("Added to circle!"))
       |> assign(
         members:
           Map.merge(
             %{id => subject},
             e(assigns(socket), :members, %{})
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
