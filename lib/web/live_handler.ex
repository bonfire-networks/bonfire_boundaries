defmodule Bonfire.Boundaries.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler
  import Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Grants

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
          |> assign_flash(:info, Enum.join([a, b, c, d] |> filter_empty([]), "\n"))
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
          |> assign_flash(:info, status)
      }
    end
  end

  def handle_event("block", %{"id" => id} = attrs, socket) when is_binary(id) do
    with {:ok, status} <- Bonfire.Boundaries.Blocks.block(id, maybe_to_atom(attrs["block_type"]), socket) do
      Bonfire.UI.Common.OpenModalLive.close()
      {:noreply,
          socket
          |> assign_flash(:info, status)
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
          |> assign_flash(:info, status)
      }
    end
  end

  def handle_event("unblock", %{"id" => id} = attrs, socket) when is_binary(id) do
    with {:ok, status} <- Bonfire.Boundaries.Blocks.unblock(id, maybe_to_atom(attrs["block_type"]), socket) do
      {:noreply,
          socket
          |> assign_flash(:info, status)
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

  def handle_event("circle_create", %{"name"=>name} = attrs, socket) do
    circle_create(Map.merge(attrs, %{named: %{name: name}}), socket)
  end

  def handle_event("circle_create", attrs, socket) do
    circle_create(attrs, socket)
  end

  def circle_create(attrs, socket) do
    with {:ok, %{id: id} = circle} <-
      Circles.create(current_user(socket), attrs) do
        # Bonfire.UI.Common.OpenModalLive.close()

        {:noreply,
          socket
          |> assign_flash(:info, "Circle created!")
          |> assign(
            circles: [circle] ++ e(socket.assigns, :circles, []),
            section: nil
          )
          |> maybe_add_to_acl(circle)
          |> maybe_redirect_to("/settings/circle/"<>id, attrs)
        }
    end
  end

  def handle_event("circle_edit", %{"circle" => circle_params}, socket) do
    # params = input_to_atoms(params)
    id = ulid!(e(socket.assigns, :circle, nil))

    with {:ok, _circle} <- Circles.edit(id, current_user(socket), %{encircles: e(circle_params, "encircle", [])}) do

      {:noreply,
        socket
        |> assign_flash(:info, "OK")
      }

    end
  end

  def handle_event("remove_from_circle", %{"subject_id" => subject}, socket) do
    id = ulid!(e(socket.assigns, :circle, nil))

    with {:ok, _circle} <-
      Circles.remove_from_circles(subject, id) do

      {:noreply,
        socket
        |> assign_flash(:info, l "Member was removed")
        |> redirect_to("/settings/circles")
      }

    end
  end

  def handle_event("circle_delete", _, socket) do
    id = ulid!(e(socket.assigns, :circle, nil))

    with {:ok, _circle} <-
      Circles.delete(id, current_user(socket)) |> debug do

      {:noreply,
        socket
        |> assign_flash(:info, l "Deleted")
        |> redirect_to("/settings/circles")
      }
    end
  end

  def handle_event("circle_soft_delete", _, socket) do
    id = ulid!(e(socket.assigns, :circle, nil))

    with {:ok, _circle} <-
      Circles.soft_delete(id, current_user(socket)) |> debug do

      {:noreply,
        socket
        |> assign_flash(:info, l "Archived")
        |> redirect_to("/settings/circles")
      }
    end
  end

  def handle_event("acl_soft_delete", _, socket) do
    id = ulid!(e(socket.assigns, :acl, nil))

    with {:ok, _} <-
      Acls.soft_delete(id, current_user(socket)) |> debug do

      {:noreply,
        socket
        |> assign_flash(:info, l "Archived")
        |> redirect_to("/settings/acls")
      }
    end
  end

  def handle_event("acl_delete", _, socket) do
    id = ulid!(e(socket.assigns, :acl, nil))

    with {:ok, _} <-
      Acls.delete(id, current_user(socket)) |> debug do

      {:noreply,
        socket
        |> assign_flash(:info, l "Deleted")
        |> redirect_to("/settings/acls")
      }
    end
  end

  def handle_event("acl_create", %{"name"=>name} = attrs, socket) do
    acl_create(Map.merge(attrs, %{named: %{name: name}}), socket)
  end

  def handle_event("acl_create", attrs, socket) do
    acl_create(attrs, socket)
  end

  def acl_create(attrs, socket) do
    with {:ok, %{id: id} = acl} <-
      Acls.create(attrs, current_user: current_user(socket)) do
        # Bonfire.UI.Common.OpenModalLive.close()

        {:noreply,
          socket
          |> assign(
            acls: [acl] ++ e(socket.assigns, :acls, []),
            edit_acl_id: id,
            section: nil
            )
          |> assign_flash(:info, l "Boundary created!")
          |> maybe_redirect_to("/settings/acl/"<>id, attrs)
        }
    end
  end

  def handle_event("remove_from_acl", %{"subject_id" => subject}, socket) do
    remove_from_acl(subject, socket)
  end

  def remove_from_acl(subject, socket) do
    # IO.inspect(subject, label: "ULLID")
    acl_id = ulid!(e(socket.assigns, :acl, nil))
    subject_id = ulid!(subject)

    socket = with {del, _} when is_integer(del) and del >0 <- Grants.remove_subject_from_acl(subject, acl_id) do
      socket
      |> assign_flash(:info, l "Removed from boundary")
      # |> redirect_to("/settings/acl/#{id}")
    else _ ->
      socket
      |> assign_flash(:info, l "No permissions removed from boundary")
    end

    {:noreply,
        socket
        |> assign(
          subjects: Enum.reject(e(socket.assigns, :subjects, []), &( ulid(&1)==subject_id ))
        )
      }
  end

  def add_to_acl(id, socket) do
    {:noreply,
      do_add_to_acl(socket, %{id: id, name: e(socket.assigns, :suggestions, id, nil)})
    }
  end

  defp maybe_add_to_acl(socket, %{} = subject) do
    if e(socket.assigns, :acl, nil) do
      do_add_to_acl(socket, subject)
    else
      socket
    end
  end

  defp do_add_to_acl(socket, %{} = subject) do
    id = ulid(subject)
    |> debug("id")
    subject_map = %{id=> %{subject: subject}}
    subject_name = subject_name(subject)
    |> debug("name")

    socket
      |> assign(
        subjects: ([subject] ++ e(socket.assigns, :subjects, [])) |> Enum.uniq_by(&ulid/1),
        suggestions: Map.put(e(socket.assigns, :suggestions, %{}), id, subject_name), # so tagify doesn't remove it as invalid
        list: e(socket.assigns, :list, %{}) |> Enum.map(
        fn
          {verb_id, %{verb: verb, subject_grants: subject_grants}} ->
            {
              verb_id,
              %{
                verb: verb,
                subject_grants: Map.merge(subject_grants, subject_map)
              }
            }

          {verb_id, %Bonfire.Data.AccessControl.Verb{} = verb} ->
            {
              verb_id,
              %{
                verb: verb,
                subject_grants: subject_map
              }
            }
        end) |> Map.new() #|> debug
        # list: Map.merge(e(socket.assigns, :list, %{}), %{id=> %{subject: %{name: e(socket.assigns, :suggestions, id, nil)}}}) #|> debug
      )
      |> assign_flash(:info, l "Added to boundary")
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


  def maybe_preload_and_check_boundaries(list_of_assigns, caller_module \\ nil) do
    list_of_assigns
    |> maybe_check_boundaries(caller_module)
    |> maybe_preload_boundaries(caller_module)
  end


  def maybe_check_boundaries(list_of_assigns, caller_module \\ nil) do
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

    if list_of_ids do
      debug(list_of_ids, "list_of_ids (check via #{caller_module})")

      my_visible_ids = if current_user,
        do: Bonfire.Boundaries.load_pointers(list_of_ids, current_user: current_user)
          |> Enum.map(&ulid/1),
        else: []

      debug(my_visible_ids, "my_visible_ids")

      list_of_assigns
      |> Enum.map(fn assigns ->
        object_id = ulid(the_object(assigns))
        if object_id in list_of_ids and object_id not in my_visible_ids do
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
    else
      debug("skip")
      list_of_assigns
    end
  end

  def maybe_preload_boundaries(list_of_assigns, caller_module \\ nil) do
    current_user = current_user(List.first(list_of_assigns))
    # |> debug("current_user")

    list_of_objects = list_of_assigns
    |> Enum.reject(&e(&1, :object_boundary, nil)) # ignore objects for which a boundary is already loaded (you can also set object_boundary to :skip in your component assigns to not preload them here)
    |> Enum.map(&the_object/1)
    # |> debug("list_of_objects")

    list_of_ids = list_of_objects
    |> Enum.map(&ulid/1)
    |> Enum.uniq()
    |> filter_empty(nil)
    |> debug("list_of_ids (preload via #{caller_module})")

    my_states = if list_of_ids && current_user,
      do: boundaries_on_objects(list_of_ids),
      else: %{}

    debug(my_states, "boundaries")

    list_of_assigns
    |> Enum.map(fn assigns ->
      object_id = ulid(the_object(assigns))
      previous_value = e(assigns, :object_boundary, nil)
      # |> debug("previous_value")

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

  def boundaries_on_objects(list_of_ids) do
    Bonfire.Boundaries.Controlleds.list_presets_on_objects(list_of_ids)
  end

  defp the_object(assigns) do
    e(assigns, :object, nil) || e(assigns, :activity, :object, nil) || e(assigns, :object_id, nil) || e(assigns, :activity, :object_id, nil)
  end

  def maybe_redirect_to(socket, _, %{"no_redirect" => r}) when r !="" do
    socket
  end
  def maybe_redirect_to(socket, path, _attrs) do
    socket
    |> redirect_to(path)
  end

  def subject_name(subject) do
    e(subject, :named, :name, nil) || e(subject, :stereotyped, :named, :name, nil) || e(subject, :profile, :name, nil) || e(subject, :character, :username, nil) || e(subject, :name, nil) || ulid(subject)
  end

end
