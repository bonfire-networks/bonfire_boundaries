defmodule Bonfire.Boundaries.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler
  use Untangle
  import Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Grants

  def handle_event("blocks", %{"id" => id} = attrs, socket)
      when is_binary(id) do
    info(attrs)
    current_user = current_user_required!(socket)
    opts = [current_user: current_user]

    can_instance_wide =
      Bonfire.Boundaries.can?(current_user, :block, :instance) ||
        is_admin?(current_user)

    with {:ok, a} <-
           if(attrs["silence"],
             do: Bonfire.Boundaries.Blocks.block(id, :silence, opts),
             else: {:ok, nil}
           ),
         {:ok, b} <-
           if(attrs["ghost"],
             do: Bonfire.Boundaries.Blocks.block(id, :ghost, opts),
             else: {:ok, nil}
           ),
         {:ok, c} <-
           if(can_instance_wide && attrs["instance_wide"]["silence"],
             do: Bonfire.Boundaries.Blocks.block(id, :silence, :instance_wide),
             else: {:ok, nil}
           ),
         {:ok, d} <-
           if(can_instance_wide && attrs["instance_wide"]["ghost"],
             do: Bonfire.Boundaries.Blocks.block(id, :ghost, :instance_wide),
             else: {:ok, nil}
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      {:noreply, assign_flash(socket, :info, Enum.join(filter_empty([a, b, c, d], []), "\n"))}
    end
  end

  def handle_event("block", %{"id" => id, "scope" => scope} = attrs, socket)
      when is_binary(id) do
    current_user = current_user_required!(socket)

    can_instance_wide =
      Bonfire.Boundaries.can?(current_user, :block, :instance) ||
        is_admin?(current_user)

    with {:ok, status} <-
           (if can_instance_wide do
              Bonfire.Boundaries.Blocks.block(
                id,
                maybe_to_atom(attrs["block_type"]),
                maybe_to_atom(scope) || socket
              )
            else
              debug("not admin, fallback to user-level block")

              Bonfire.Boundaries.Blocks.block(
                id,
                maybe_to_atom(attrs["block_type"]),
                socket
              )
            end) do
      Bonfire.UI.Common.OpenModalLive.close()

      {:noreply, assign_flash(socket, :info, status)}
    end
  end

  def handle_event("block", %{"id" => id} = attrs, socket) when is_binary(id) do
    with {:ok, status} <-
           Bonfire.Boundaries.Blocks.block(
             id,
             maybe_to_atom(attrs["block_type"]),
             socket
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      {:noreply, assign_flash(socket, :info, status)}
    end
  end

  def handle_event("unblock", %{"id" => id, "scope" => scope} = attrs, socket)
      when is_binary(id) do
    unblock(id, maybe_to_atom(attrs["block_type"]), scope, socket)
  end

  def handle_event("unblock", %{"id" => id} = attrs, socket)
      when is_binary(id) do
    unblock(id, maybe_to_atom(attrs["block_type"]), socket.assigns[:scope], socket)
  end

  def handle_event("circle_create", %{"name" => name} = attrs, socket) do
    circle_create(Map.merge(attrs, %{named: %{name: name}}), socket)
  end

  def handle_event("circle_create", attrs, socket) do
    circle_create(attrs, socket)
  end

  def handle_event("open_boundaries", _params, socket) do
    debug("open_boundaries")
    {:noreply, assign(socket, :open_boundaries, true)}
  end

  def handle_event("close_boundaries", _params, socket) do
    debug("close_boundaries")
    {:noreply, assign(socket, :open_boundaries, false)}
  end

  def handle_event("select_boundary", %{"id" => acl_id} = params, socket) do
    debug(acl_id, "select_boundary")

    {:noreply,
     assign(
       socket,
       :to_boundaries,
       Bonfire.Boundaries.Web.SetBoundariesLive.set_clean_boundaries(
         e(socket.assigns, :to_boundaries, []),
         acl_id,
         e(params, "name", acl_id)
       )
     )}
  end

  def handle_event("remove_boundary", %{"id" => id} = _params, socket) do
    debug(id, "remove_boundary")

    {:noreply,
     assign(
       socket,
       :to_boundaries,
       e(socket.assigns, :to_boundaries, [])
       |> Keyword.drop([id])
     )}
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

  def handle_event(action, %{"id" => selected} = _attrs, socket)
      when action in ["select", "select_circle"] and is_binary(selected) do
    {:noreply,
     assign(socket,
       to_circles: set_circles([selected], e(socket, :assigns, :to_circles, []), true)
     )}
  end

  def handle_event(action, %{"id" => deselected} = _attrs, socket)
      when action in ["deselect", "remove_circle"] and is_binary(deselected) do
    {:noreply,
     assign(socket,
       to_circles:
         remove_from_circle_tuples(
           [deselected],
           e(socket, :assigns, :to_circles, [])
         )
     )}
  end

  def handle_event("circle_edit", %{"circle" => circle_params}, socket) do
    # params = input_to_atoms(params)
    id = ulid!(e(socket.assigns, :circle, nil))

    with {:ok, _circle} <-
           Circles.edit(id, current_user_required!(socket), %{
             encircles: e(circle_params, "encircle", [])
           }) do
      {:noreply, assign_flash(socket, :info, "OK")}
    end
  end

  def handle_event("remove_from_circle", %{"subject_id" => subject}, socket) do
    id = ulid!(e(socket.assigns, :circle, nil))

    with {:ok, _circle} <-
           Circles.remove_from_circles(subject, id) do
      {:noreply,
       socket
       |> assign_flash(:info, l("Member was removed"))
       |> redirect_to("/boundaries/circles")}
    end
  end

  def handle_event("circle_delete", _, socket) do
    id = ulid!(e(socket.assigns, :circle, nil))

    with {:ok, _circle} <-
           Circles.delete(id, current_user_required!(socket)) |> debug() do
      {:noreply,
       socket
       |> assign_flash(:info, l("Deleted"))
       |> redirect_to("/boundaries/circles")}
    end
  end

  def handle_event("circle_soft_delete", _, socket) do
    id = ulid!(e(socket.assigns, :circle, nil))

    with {:ok, _circle} <-
           Circles.soft_delete(id, current_user_required!(socket)) |> debug() do
      {:noreply,
       socket
       |> assign_flash(:info, l("Archived"))
       |> redirect_to("/boundaries/circles")}
    end
  end

  def handle_event("edit", attrs, socket) do
    with {:ok, circle} <-
           Circles.edit(
             e(socket.assigns, :circle, nil),
             current_user_required!(socket),
             attrs
           ) do
      {:noreply,
       socket
       |> assign_flash(:info, l("Edited!"))
       |> assign(circle: circle)}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not edit circle"))}
    end
  end

  def handle_event("acl_soft_delete", _, socket) do
    id = ulid!(e(socket.assigns, :acl, nil))

    with {:ok, _} <-
           Acls.soft_delete(id, current_user_required!(socket)) |> debug() do
      {:noreply,
       socket
       |> assign_flash(:info, l("Archived"))
       |> redirect_to("/boundaries/acls")}
    end
  end

  def handle_event("acl_delete", _, socket) do
    id = ulid!(e(socket.assigns, :acl, nil))

    with {:ok, _} <-
           Acls.delete(id, current_user_required!(socket)) |> debug() do
      {:noreply,
       socket
       |> assign_flash(:info, l("Deleted"))
       |> redirect_to("/boundaries/acls")}
    end
  end

  def unblock(id, block_type, scope, socket)
      when is_binary(id) do
    current_user = current_user_required!(socket)

    can_instance_wide =
      Bonfire.Boundaries.can?(current_user, :block, :instance) ||
        is_admin?(current_user)

    with {:ok, status} <-
           (if can_instance_wide do
              Bonfire.Boundaries.Blocks.unblock(
                id,
                block_type,
                maybe_to_atom(scope) || socket
              )
            else
              debug("not admin, fallback to user-level block")

              Bonfire.Boundaries.Blocks.unblock(
                id,
                block_type,
                socket
              )
            end) do
      {:noreply, assign_flash(socket, :info, status)}
    end
  end

  def handle_event("acl_create", %{"name" => name} = attrs, socket) do
    acl_create(Map.merge(attrs, %{named: %{name: name}}), socket)
  end

  def handle_event("acl_create", attrs, socket) do
    acl_create(attrs, socket)
  end

  def acl_create(attrs, socket) do
    with {:ok, %{id: id} = acl} <-
           Acls.create(attrs,
             current_user: e(socket.assigns, :scope, nil) || current_user_required!(socket)
           ) do
      # Bonfire.UI.Common.OpenModalLive.close()

      {:noreply,
       socket
       |> assign(
         acls: [acl] ++ e(socket.assigns, :acls, []),
         edit_acl_id: id,
         section: nil
       )
       |> assign_flash(:info, l("Boundary created!"))
       |> maybe_redirect_to("/boundaries/acl/" <> id, attrs)}
    end
  end

  def circle_create(attrs, socket) do
    with {:ok, %{id: id} = circle} <-
           Circles.create(
             e(socket.assigns, :scope, nil) || current_user_required!(socket),
             attrs
           ) do
      # Bonfire.UI.Common.OpenModalLive.close()

      socket
      |> assign_flash(:info, "Circle created!")
      |> assign(
        circles: [circle] ++ e(socket.assigns, :circles, []),
        section: nil
      )
      |> maybe_redirect_to("/boundaries/circle/" <> id, attrs)
      |> maybe_add_to_acl(circle)
    end
  end

  defp maybe_add_to_acl(socket, subject) do
    if e(socket.assigns, :acl, nil) do
      Bonfire.Boundaries.Web.AclLive.add_to_acl(subject, socket)
    else
      {:noreply, socket}
    end
  end

  def set_circles(selected_circles, previous_circles, add_to_previous \\ false) do
    # debug(previous_circles: previous_circles)
    # selected_circles = Enum.uniq(selected_circles)
    # debug(selected_circles: selected_circles)

    previous_ids =
      Enum.map(previous_circles, fn
        {_name, id} -> id
        _ -> nil
      end)

    # debug(previous_ids: previous_ids)

    public = Bonfire.Boundaries.Circles.circles()[:guest]

    # public/guests defaults to also being visible to local users and federating
    selected_circles =
      if public in selected_circles and public not in previous_ids do
        selected_circles ++
          [
            Bonfire.Boundaries.Circles.circles()[:local],
            Bonfire.Boundaries.Circles.circles()[:admin],
            Bonfire.Boundaries.Circles.circles()[:activity_pub]
          ]
      else
        selected_circles
      end

    # debug(new_selected_circles: selected_circles)

    existing =
      if add_to_previous,
        do: previous_circles,
        else: known_circle_tuples(selected_circles, previous_circles)

    # fix this ugly thing
    (existing ++
       Enum.map(selected_circles, &Bonfire.Boundaries.Circles.get_tuple/1))
    |> Utils.filter_empty([])
    |> Enum.uniq()

    # |> debug()
  end

  def known_circle_tuples(selected_circles, previous_circles) do
    Enum.filter(previous_circles, fn
      {_name, id} -> id in selected_circles
      _ -> nil
    end)
  end

  def remove_from_circle_tuples(deselected_circles, previous_circles) do
    Enum.filter(previous_circles, fn
      {_name, id} -> id not in deselected_circles
      _ -> nil
    end)
  end

  def maybe_preload_and_check_boundaries(list_of_assigns, opts \\ []) do
    list_of_assigns
    |> maybe_check_boundaries(opts)
    |> preload(opts)
  end

  @decorate time()
  def maybe_check_boundaries(list_of_assigns, opts \\ []) do
    current_user = current_user(List.first(list_of_assigns))

    # |> debug("current_user")

    list_of_objects =
      list_of_assigns
      # |> debug("list_of_assigns")
      # only check when explicitly asked
      |> Enum.reject(&(e(&1, :check_object_boundary, nil) != true))
      |> Enum.map(&the_object/1)

    # |> debug("list_of_objects")

    list_of_ids =
      list_of_objects
      |> Enum.map(&ulid_or_acl/1)
      |> Enum.uniq()
      |> filter_empty(nil)

    if list_of_ids do
      debug(list_of_ids, "list_of_ids (check via #{opts[:caller_module]})")

      my_visible_ids =
        if current_user,
          do:
            Bonfire.Boundaries.load_pointers(list_of_ids,
              current_user: current_user,
              verbs: e(opts, :verbs, [:read])
            )
            |> Enum.map(&ulid/1),
          else: []

      debug(my_visible_ids, "my_visible_ids")

      Enum.map(list_of_assigns, fn assigns ->
        object_id = ulid(the_object(assigns))

        if object_id in list_of_ids and object_id not in my_visible_ids do
          # not allowed
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
          # allowed
          assigns
          |> Map.put(
            :boundary_can,
            true
          )
          # to avoid checking again
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

  defp ulid_or_acl(:instance) do
    Bonfire.Boundaries.Fixtures.instance_acl()
  end

  defp ulid_or_acl(obj) do
    ulid(obj)
  end

  def preload(list_of_assigns, opts \\ []) do
    if current_user(List.first(list_of_assigns)) do
      preload_assigns_async(
        list_of_assigns,
        &assigns_to_params/1,
        &do_preload/3,
        opts ++ [skip_if_set: :object_boundary]
      )
    else
      # no need to preload list of boundaries for guests
      list_of_assigns
    end
  end

  defp assigns_to_params(assigns) do
    object = the_object(assigns)

    %{
      component_id: assigns.id,
      object: object || e(assigns, :object_id, nil),
      object_id: e(assigns, :object_id, nil) || ulid(object),
      previous_value: e(assigns, :object_boundary, nil)
    }
  end

  @decorate time()
  defp do_preload(list_of_components, list_of_ids, current_user) do
    my_states =
      if is_list(list_of_ids) and list_of_ids != [],
        do: boundaries_on_objects(list_of_ids, current_user),
        else: %{}

    debug(my_states, "boundaries_on_objects")

    list_of_components
    |> Map.new(fn component ->
      {component.component_id,
       %{
         object_boundary:
           Map.get(my_states, component.object_id) || component.previous_value || false
       }}
    end)
  end

  def boundaries_on_objects(list_of_ids, current_user) do
    presets =
      Bonfire.Boundaries.Controlleds.list_presets_on_objects(list_of_ids)
      |> debug("presets")

    if not is_nil(current_user) do
      # WIP: show user's computed permission instead of preset if we have current_user
      # case Bonfire.Boundaries.Controlleds.list_on_objects_by_subject(list_of_ids, current_user) do
      case Bonfire.Boundaries.my_grants_on(current_user, list_of_ids) do
        custom when custom != %{} and custom != [] ->
          custom
          |> Map.new(&{&1.object_id, Map.take(&1, [:verbs, :value])})
          |> debug("my_grants_on")
          |> deep_merge(presets)
          |> debug("merged")

        _empty ->
          presets
      end
    else
      presets
    end
  end

  def maybe_redirect_to(socket, _, %{"no_redirect" => r}) when r != "" do
    socket
  end

  def maybe_redirect_to(socket, path, _attrs) do
    redirect_to(
      socket,
      path
    )
  end

  def subject_name(subject) do
    e(subject, :named, :name, nil) ||
      e(subject, :stereotyped, :named, :name, nil) ||
      e(subject, :profile, :name, nil) || e(subject, :character, :username, nil) ||
      e(subject, :name, nil) || ulid(subject)
  end
end
