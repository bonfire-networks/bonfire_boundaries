defmodule Bonfire.Boundaries.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler
  import Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.Circles

  def handle_event("blocks", %{"id" => id} = attrs, socket) when is_binary(id) do
    info(attrs)
    current_user = current_user(socket)
    opts = [current_user: current_user]

    with {:ok, a} <- (if attrs["silence"], do: Bonfire.Boundaries.Blocks.block(id, :silence, opts), else: {:ok, nil}),
    {:ok, b} <- (if attrs["ghost"], do: Bonfire.Boundaries.Blocks.block(id, :ghost, opts), else: {:ok, nil}),
    {:ok, c} <- (if is_admin?(current_user) && attrs["instance_wide"]["silence"], do: Bonfire.Boundaries.Blocks.block(id, :silence, :instance_wide), else: {:ok, nil}),
    {:ok, d} <- (if is_admin?(current_user) && attrs["instance_wide"]["ghost"], do: Bonfire.Boundaries.Blocks.block(id, :ghost, :instance_wide), else: {:ok, nil}) do
      Bonfire.UI.Common.OpenModalLive.close()
      {:noreply,
          socket
          |> put_flash(:info, Enum.join([a, b, c, d] |> filter_empty([]), "\n"))
      }
    end
  end

  def handle_event("block", %{"id" => id, "scope" => scope} = attrs, socket) when is_binary(id) do
    with {:ok, status} <- (
      if is_admin?(current_user(socket)) do
      Bonfire.Boundaries.Blocks.block(id, maybe_to_atom(attrs["block_type"]), maybe_to_atom(scope) || socket)
    else
      debug("not admin, fallback to user-level block")
      Bonfire.Boundaries.Blocks.block(id, maybe_to_atom(attrs["block_type"]), socket)
    end
    ) do
      Bonfire.UI.Common.OpenModalLive.close()
      {:noreply,
          socket
          |> put_flash(:info, status)
      }
    end
  end

  def handle_event("block", %{"id" => id} = attrs, socket) when is_binary(id) do
    with {:ok, status} <- Bonfire.Boundaries.Blocks.block(id, maybe_to_atom(attrs["block_type"]), socket) do
      Bonfire.UI.Common.OpenModalLive.close()
      {:noreply,
          socket
          |> put_flash(:info, status)
      }
    end
  end

    def handle_event("unblock", %{"id" => id, "scope" => scope} = attrs, socket) when is_binary(id) do
    with {:ok, status} <- (
      if is_admin?(current_user(socket)) do
      Bonfire.Boundaries.Blocks.unblock(id, maybe_to_atom(attrs["block_type"]), maybe_to_atom(scope) || socket)
    else
      debug("not admin, fallback to user-level block")
      Bonfire.Boundaries.Blocks.unblock(id, maybe_to_atom(attrs["block_type"]), socket)
    end
    ) do
      {:noreply,
          socket
          |> put_flash(:info, status)
      }
    end
  end

  def handle_event("unblock", %{"id" => id} = attrs, socket) when is_binary(id) do
    with {:ok, status} <- Bonfire.Boundaries.Blocks.unblock(id, maybe_to_atom(attrs["block_type"]), socket) do
      {:noreply,
          socket
          |> put_flash(:info, status)
      }
    end
  end

  # def handle_event("input", %{"circles" => selected_circles} = _attrs, socket) when is_list(selected_circles) and length(selected_circles)>0 do

  #   previous_circles = e(socket, :assigns, :to_circles, []) #|> Enum.uniq()

  #   new_circles = set_circles(selected_circles, previous_circles)

  #   {:noreply,
  #       socket
  #       |> assign_global(
  #         to_circles: new_circles
  #       )
  #   }
  # end

  # def handle_event("input", _attrs, socket) do # no circle
  #   {:noreply,
  #     socket
  #       |> assign_global(
  #         to_circles: []
  #       )
  #   }
  # end

  def handle_event("select", %{"id" => selected} = _attrs, socket) when is_binary(selected) do

    previous_circles = e(socket, :assigns, :to_circles, []) #|> IO.inspect

    new_circles = set_circles([selected], previous_circles, true) #|> IO.inspect

    {:noreply,
        socket
        |> assign_global(
          to_circles: new_circles
        )
    }
  end

  def handle_event("deselect", %{"id" => deselected} = _attrs, socket) when is_binary(deselected) do

    new_circles = remove_from_circle_tuples([deselected], e(socket, :assigns, :to_circles, [])) #|> IO.inspect

    {:noreply,
        socket
        |> assign_global(
          to_circles: new_circles
        )
    }
  end

  def handle_event("create_circle", %{"name" => name}, socket) do
  # params = input_to_atoms(params)

    with {:ok, %{id: id} = _circle} <-
      Circles.create(current_user(socket), name) do

          {:noreply,
          socket
          |> put_flash(:info, "Circle create!")
          |> push_redirect(to: "/settings/circle/"<>id)
          }

    end
  end

  def handle_event("member_update", %{"circle" => %{"id" => id} = params}, socket) do
    # params = input_to_atoms(params)

    with {:ok, _circle} <-
      Circles.update(id, current_user(socket), %{encircles: e(params, "encircle", [])}) do

          {:noreply,
          socket
          |> put_flash(:info, "OK")
          }

    end
  end


  def set_circles(selected_circles, previous_circles, add_to_previous \\ false) do

    # debug(previous_circles: previous_circles)
    # selected_circles = Enum.uniq(selected_circles)

    # debug(selected_circles: selected_circles)

    previous_ids = previous_circles |> Enum.map(fn
        {_name, id} -> id
        _ -> nil
      end)
    # debug(previous_ids: previous_ids)

    public = Bonfire.Boundaries.Circles.circles()[:guest]

    selected_circles = if public in selected_circles and public not in previous_ids do # public/guests defaults to also being visible to local users and federating
      selected_circles ++ [
        Bonfire.Boundaries.Circles.circles()[:local],
        Bonfire.Boundaries.Circles.circles()[:admin],
        Bonfire.Boundaries.Circles.circles()[:activity_pub]
      ]
    else
      selected_circles
    end

    # debug(new_selected_circles: selected_circles)

    existing = if add_to_previous, do: previous_circles, else: known_circle_tuples(selected_circles, previous_circles)


    # fix this ugly thing
    (
     existing
     ++
     Enum.map(selected_circles, &Bonfire.Boundaries.Circles.get_tuple/1)
    )
    |> Utils.filter_empty([]) |> Enum.uniq()
    # |> debug()
  end

  def known_circle_tuples(selected_circles, previous_circles) do
    previous_circles
    |> Enum.filter(fn
        {_name, id} -> id in selected_circles
        _ -> nil
      end)
  end

  def remove_from_circle_tuples(deselected_circles, previous_circles) do
    previous_circles
    |> Enum.filter(fn
        {_name, id} -> id not in deselected_circles
        _ -> nil
      end)
  end


  def preload_assigns(list_of_assigns) do
    list_of_assigns
    |> maybe_check_boundaries()
    |> maybe_preload_boundaries()
  end


  def maybe_check_boundaries(list_of_assigns) do
    current_user = current_user(List.first(list_of_assigns))
    # |> debug("current_user")

    list_of_objects = list_of_assigns
    |> Enum.reject(&e(&1, :check_object_boundary, nil) !=true) # only check when explicitly asked
    |> Enum.map(&the_object/1)
    # |> debug("list_of_objects")

    list_of_ids = list_of_objects
    |> Enum.map(&ulid/1)
    |> Enum.uniq()
    |> filter_empty(nil)
    |> debug("list_of_ids")

    my_visible_ids = if list_of_ids && current_user,
      do: Bonfire.Boundaries.load_pointers(list_of_ids, current_user: current_user)
        |> Enum.map(&ulid/1),
      else: %{}

    debug(my_visible_ids, "my_visible_ids")

    list_of_assigns
    |> Enum.map(fn assigns ->
      object_id = ulid(the_object(assigns))
      if list_of_ids && (object_id in list_of_ids and object_id not in my_visible_ids) do
        assigns
        |> Map.put(
          :activity,
          nil
        )
        |> Map.put(
          :object,
          nil
        )
        |> Map.put(
          :object_boundary,
          :not_visible
        )
      else
        # avoid checking again
        assigns
        |> Map.put(
          :check_object_boundary,
          false
        )
      end
    end)
  end

  def maybe_preload_boundaries(list_of_assigns) do
    current_user = current_user(List.first(list_of_assigns))
    # |> debug("current_user")

    list_of_objects = list_of_assigns
    |> Enum.reject(&e(&1, :object_boundary, nil)) # ignore objects for which a boundary is already set (you can also set object_boundary to :skip in your component assigns to not preload them here)
    |> Enum.map(&the_object/1)
    # |> debug("list_of_objects")

    list_of_ids = list_of_objects
    |> Enum.map(&ulid/1)
    |> Enum.uniq()
    |> filter_empty(nil)
    |> debug("list_of_ids")

    my_states = if list_of_ids && current_user,
      do: Bonfire.Boundaries.Controlleds.list_on_objects(list_of_ids)
        |> Map.new(fn c -> { # Map.new discards duplicates for the same key, which is convenient for now as we only display one ACL (note that the order_by in the `list_on_objects` query matters)
          e(c, :id, nil),
          e(c, :acl, nil)
        } end),
      else: %{}

    # debug(my_states, "boundaries")

    list_of_assigns
    |> Enum.map(fn assigns ->
      object_id = ulid(the_object(assigns))
      previous_value = e(assigns, :object_boundary, nil)

      assigns
      # |> Map.put(
      #   :object_boundaries,
      #   Map.get(my_states, object_id)
      # )
      |> Map.put(
        :object_boundary,
        e(my_states, object_id, :named, nil) || previous_value || :none
      )
    end)
  end

  defp the_object(assigns) do
    e(assigns, :object, nil) || e(assigns, :activity, :object, nil) || e(assigns, :object_id, nil) || e(assigns, :activity, :object_id, nil)
  end

end
