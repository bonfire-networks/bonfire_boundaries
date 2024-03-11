defmodule Bonfire.Boundaries.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler
  use Untangle
  # import Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Roles
  # alias Bonfire.Boundaries.Grants

  def handle_event("blocks", %{"id" => id} = attrs, socket)
      when is_binary(id) do
    info(attrs)
    current_user = current_user_required!(socket)
    opts = [current_user: current_user]

    can_instance_wide = Bonfire.Boundaries.can?(socket.assigns[:__context__], :block, :instance)

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
    # current_user = current_user_required!(socket)

    can_instance_wide = Bonfire.Boundaries.can?(socket.assigns[:__context__], :block, :instance)

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

  def handle_event("acl_create", %{"name" => name} = attrs, socket) do
    acl_create(Map.merge(attrs, %{named: %{name: name}}), socket)
  end

  def handle_event("acl_create", attrs, socket) do
    acl_create(attrs, socket)
  end

  def handle_event("open_boundaries", _params, socket) do
    debug("open_boundaries")
    {:noreply, assign(socket, :open_boundaries, true)}
  end

  def handle_event("close_boundaries", _params, socket) do
    debug("close_boundaries")
    {:noreply, assign(socket, :open_boundaries, false)}
  end

  def handle_event("replace_boundary", %{"id" => acl_id} = params, socket) do
    debug(acl_id, "replace_boundary")

    {:noreply,
     assign(
       socket,
       :to_boundaries,
       [{acl_id, e(params, "name", acl_id)}]
     )}
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
    {:noreply, Bonfire.Boundaries.LiveHandler.set_circles_tuples(:to_circles, [selected], socket)}
    #
    #  assign(socket,
    #    to_circles: set_circles([selected], e(socket, :assigns, :to_circles, []), true)
    #  )
  end

  def handle_event(
        "select",
        %{"to_circles" => to_circles, "exclude_circles" => exclude_circles} = _params,
        socket
      ) do
    {:noreply,
     socket
     |> Bonfire.Boundaries.LiveHandler.set_circles_tuples(:to_circles, to_circles, ...)
     |> Bonfire.Boundaries.LiveHandler.set_circles_tuples(:exclude_circles, exclude_circles, ...)}
  end

  def handle_event("select", %{"to_circles" => circles} = _params, socket) do
    {:noreply,
     socket
     |> Bonfire.Boundaries.LiveHandler.set_circles_tuples(:to_circles, circles, ...)}
  end

  def handle_event("select", %{"exclude_circles" => circles} = _params, socket) do
    {:noreply,
     Bonfire.Boundaries.LiveHandler.set_circles_tuples(:exclude_circles, circles, socket)}
  end

  def handle_event("select", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(action, %{"id" => deselected} = attrs, socket)
      when action in ["deselect", "remove_circle"] and is_binary(deselected) do
    field = e(attrs, "field", nil) |> Types.maybe_to_atom() || :to_circles

    {:noreply,
     assign(
       socket,
       field,
       remove_from_circle_tuples(
         [deselected],
         e(socket, :assigns, field, [])
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
    _current_user = current_user_required!(socket)
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

  def handle_event("load_more", attrs, socket) do
    scope = scope_origin(socket)

    %{page_info: page_info, edges: edges} = my_circles_paginated(scope, input_to_atoms(attrs))

    {:noreply,
     socket
     |> assign(
       loaded: true,
       circles: e(socket.assigns, :circles, []) ++ edges,
       page_info: page_info
     )}
  end

  # TODO
  # def handle_event("circle_soft_delete", _, socket) do
  #   id = ulid!(e(socket.assigns, :circle, nil))

  #   with {:ok, _circle} <-
  #          Circles.soft_delete(id, current_user_required!(socket)) |> debug() do
  #     {:noreply,
  #      socket
  #      |> assign_flash(:info, l("Archived"))
  #      |> redirect_to("/boundaries/circles")}
  #   end
  # end

  def handle_event("edit", attrs, socket) do
    with {:ok, circle} <-
           Circles.edit(
             e(attrs, :id, nil),
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

  def handle_event("role_create", attrs, socket) do
    current_user = current_user_required!(socket)

    scope =
      case e(socket.assigns, :scope, nil) do
        nil -> current_user
        scope -> scope
      end

    with {:ok, _} <-
           Roles.create(
             input_to_atoms(attrs),
             scope: scope,
             current_user: current_user
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      {:noreply,
       socket
       |> assign_flash(:info, "Role created!")
       |> redirect_to(current_url(socket))}
    end
  end

  def handle_event(
        "custom_from_preset_template",
        %{"boundary" => boundary, "name" => name} = _params,
        socket
      ) do
    {to_circles, exclude_circles} =
      Acls.grant_tuples_from_preset(current_user_required!(socket), boundary)
      |> Roles.split_tuples_can_cannot()
      |> debug("custom_from_preset_template")

    {:noreply,
     socket
     |> assign(
       to_circles: to_circles,
       exclude_circles: exclude_circles,
       to_boundaries: [{"custom", "#{name}*"}]
     )}
  end

  def handle_event(
        "remove_object_acl",
        %{"object_id" => object, "acl_id" => acl} = _params,
        socket
      ) do
    with {1, nil} <-
           Bonfire.Boundaries.Controlleds.remove_acls(
             object,
             acl
           )
           |> debug("removed?") do
      Bonfire.UI.Common.OpenModalLive.close()

      {
        :noreply,
        socket
        |> assign_flash(:info, l("Boundary removed!"))
        #  |> assign(
        #  )
      }
    else
      e ->
        error(e)
    end
  end

  def handle_event("add_object_acl", %{"id" => acl, "object_id" => object}, socket) do
    with {:ok, _} <-
           Bonfire.Boundaries.Controlleds.add_acls(
             object,
             acl
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      {
        :noreply,
        socket
        |> assign_flash(:info, l("Boundary added!"))
        #  |> assign(
        #  )
      }
    else
      e ->
        error(e)
    end
  end

  def unblock(id, block_type, scope, socket)
      when is_binary(id) do
    # current_user = current_user_required!(socket)

    can_instance_wide = Bonfire.Boundaries.can?(socket.assigns[:__context__], :block, :instance)

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

  def acl_create(attrs, socket) do
    current_user = current_user_required!(socket)
    scope = maybe_to_atom(e(attrs, :scope, nil))

    with {:ok, %{id: id} = acl} <-
           Acls.create(attrs,
             current_user: scope || current_user
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
       |> maybe_redirect_to(
         if(is_atom(scope) && not is_nil(scope),
           do: ~p"/boundaries/scope/instance/acl/" <> id,
           else: ~p"/boundaries/acl/" <> id
         ),
         attrs
       )}
    end
  end

  def circle_create(attrs, socket) do
    current_user = current_user_required!(socket)
    scope = maybe_to_atom(e(attrs, :scope, nil))

    with {:ok, %{id: id} = circle} <-
           Circles.create(
             scope || current_user,
             attrs
           ) do
      # Bonfire.UI.Common.OpenModalLive.close()

      socket
      |> assign_flash(:info, "Circle created!")
      |> assign(
        circles: [circle] ++ e(socket.assigns, :circles, []),
        section: nil
      )
      |> maybe_redirect_to(
        ~p"/boundaries/scope/#{if is_atom(scope) && not is_nil(scope), do: scope, else: "user"}/circle/" <>
          id,
        attrs
      )
      |> maybe_add_to_acl(circle)
    end
  end

  defp maybe_add_to_acl(socket, subject) do
    _current_user = current_user_required!(socket)

    if e(socket.assigns, :acl, nil) do
      Bonfire.Boundaries.Web.AclLive.add_to_acl(subject, socket)
    else
      {:noreply, socket}
    end
  end

  # def set_circles(selected_circles, previous_circles, add_to_previous \\ false) do
  #   # debug(previous_circles: previous_circles)
  #   # selected_circles = Enum.uniq(selected_circles)
  #   # debug(selected_circles: selected_circles)

  #   previous_ids =
  #     Enum.map(previous_circles, fn
  #       {_name, id} -> id
  #       _ -> nil
  #     end)

  #   # debug(previous_ids: previous_ids)

  #   public = Bonfire.Boundaries.Circles.circles()[:guest]

  #   # public/guests defaults to also being visible to local users and federating
  #   selected_circles =
  #     if public in selected_circles and public not in previous_ids do
  #       selected_circles ++
  #         [
  #           Bonfire.Boundaries.Circles.circles()[:local],
  #           Bonfire.Boundaries.Circles.circles()[:admin],
  #           Bonfire.Boundaries.Circles.circles()[:activity_pub]
  #         ]
  #     else
  #       selected_circles
  #     end

  #   # debug(new_selected_circles: selected_circles)

  #   existing =
  #     if add_to_previous,
  #       do: previous_circles,
  #       else: known_circle_tuples(selected_circles, previous_circles)

  #   # fix this ugly thing
  #   (existing ++
  #      Enum.map(selected_circles, &Bonfire.Boundaries.Circles.get_tuple/1))
  #   |> Enums.filter_empty([])
  #   |> Enum.uniq()

  #   # |> debug()
  # end

  # def known_circle_tuples(selected_circles, previous_circles) do
  #   Enum.filter(previous_circles, fn
  #     {%{id: id} = circle, _old_role} -> id in selected_circles
  #     {id, _role} -> id in selected_circles
  #     _ -> nil
  #   end)
  # end

  def set_circles_tuples(field, circles, socket) do
    # raise nil
    debug(circles, "set roles for #{field}")

    previous_value =
      e(socket.assigns, field, [])
      |> debug("previous_value")

    known_circles =
      previous_value
      |> Enum.map(fn
        {%{id: id} = circle, _old_role} ->
          {id, circle}

        {%{"id" => id} = circle, _old_role} ->
          {id, circle}

        _ ->
          nil
      end)
      |> debug("known_circles")

    circles =
      (circles || [])
      |> Enum.map(fn
        {circle, roles} ->
          Enum.map(roles, &{e(known_circles, id(circle), nil) || circle, &1})
      end)
      |> List.flatten()
      |> debug("computed")

    if previous_value != circles do
      socket
      |> assign(field, circles)
      |> assign(
        reset_smart_input: false
        #  ^to avoid un-reset the input
      )
      |> assign_global(
        _already_live_selected_:
          Enum.uniq(e(socket.assigns, :__context, :_already_live_selected_, []) ++ [field])
      )
    else
      socket
    end
  end

  def remove_from_circle_tuples(ids, previous_circles) do
    deselected_circles = ids(ids)

    previous_circles
    |> debug()
    |> Enum.reject(fn
      {circle, _role} ->
        id(circle) in deselected_circles

      # {_name, id} -> id(circle) in deselected_circles
      circle ->
        id(circle) in deselected_circles
        # _ -> nil
    end)
  end

  # @decorate time()
  def maybe_check_boundaries(assigns_sockets, opts \\ []) do
    current_user =
      current_user(elem(List.first(assigns_sockets), 0)) ||
        current_user(elem(List.first(assigns_sockets), 1))

    # |> debug("current_user")

    list_of_objects =
      assigns_sockets
      # |> debug("assigns_sockets")
      # only check when explicitly asked
      |> Enum.reject(&(e(&1, :check_object_boundary, nil) != true))
      |> Enum.map(&the_object/1)

    # |> debug("list_of_objects")

    list_of_ids =
      list_of_objects
      |> Enum.map(&Acls.acl_id/1)
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

      Enum.map(assigns_sockets, fn {assigns, socket} ->
        object_id = ulid(the_object(assigns))

        {if object_id in list_of_ids and object_id not in my_visible_ids do
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
         end, socket}
      end)
    else
      debug("skip")
      assigns_sockets
    end
  end

  # @decorate time()
  def update_many(assigns_sockets, opts \\ []) do
    update_many_async(
      assigns_sockets,
      update_many_opts(opts)
    )
  end

  def update_many_opts(opts \\ []) do
    opts ++
      [
        skip_if_set: :object_boundary,
        preload_status_key: :preloaded_async_boundaries,
        assigns_to_params_fn: &assigns_to_params/1,
        preload_fn: &do_preload/3
      ]
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
      # display user's computed permission if we have current_user
      case Bonfire.Boundaries.users_grants_on(current_user, list_of_ids) do
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

  def scope_origin(assigns \\ nil, socket) do
    context = e(assigns, :__context__, nil) || socket.assigns[:__context__]
    current_user = current_user(context)
    scope = e(assigns, :scope, nil) || e(socket.assigns, :scope, nil)

    if scope == :instance and
         Bonfire.Boundaries.can?(context, :assign, :instance),
       do: Bonfire.Boundaries.Fixtures.admin_circle(),
       else: current_user
  end

  def my_circles_paginated(scope, attrs \\ nil) do
    Bonfire.Boundaries.Circles.list_my_with_counts(scope,
      exclude_stereotypes: true,
      exclude_built_ins: true,
      paginate?: true,
      paginate: attrs
    )
    |> repo().maybe_preload(encircles: [subject: [:profile]])
  end

  def prepare_assigns({reply, socket}) do
    {reply, socket |> prepare_assigns()}
  end

  def prepare_assigns(socket) do
    current_user = current_user(socket.assigns)
    my_acls = e(socket.assigns[:__context__], :my_acls, nil) || my_acls(id(current_user))

    to_boundaries =
      e(socket.assigns, :to_boundaries, nil)
      |> debug("existing")
      |> Bonfire.Boundaries.boundaries_or_default(current_user: current_user, my_acls: my_acls)
      |> debug()

    socket
    |> assign_global(
      :my_acls,
      my_acls
    )
    |> assign(
      to_boundaries: to_boundaries,
      boundary_preset:
        Bonfire.Boundaries.Web.SetBoundariesLive.boundaries_to_preset(to_boundaries)
    )
  end

  def my_acls(current_user_id, opts \\ nil) do
    Bonfire.Boundaries.Acls.list_my(
      current_user_id,
      opts || Bonfire.Boundaries.Acls.opts_for_list()
    )
    |> Enum.map(fn
      %Bonfire.Data.AccessControl.Acl{id: acl_id} = acl ->
        {acl_id, acl_meta(acl)}
    end)
    |> Enum.reject(fn
      {_, %{name: nil}} -> true
      _ -> false
    end)
    |> debug("myacccl")
  end

  defp acl_meta(%{id: acl_id, stereotyped: %{stereotype_id: "1HANDP1CKEDZEPE0P1E1F0110W"}} = acl) do
    %{
      id: acl_id,
      field: :to_boundaries,
      description: e(acl, :stereotyped, :named, :name, nil),
      name: l("Follows"),
      icon: "fluent:people-list-16-filled"
    }
  end

  defp acl_meta(%{id: acl_id} = acl) do
    %{
      id: acl_id,
      field: :to_boundaries,
      description: e(acl, :extra_info, :summary, nil),
      name: e(acl, :named, :name, nil) || e(acl, :stereotyped, :named, :name, nil)
    }
  end
end
