defmodule Bonfire.Boundaries.Web.AclLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Grants
  alias Bonfire.Boundaries.LiveHandler
  # alias Bonfire.Boundaries.Integration
  require Integer

  prop acl_id, :string, default: nil
  prop edit_circle_id, :string, default: nil
  prop parent_back, :any, default: nil
  prop columns, :integer, default: 1
  prop selected_tab, :any, default: nil
  prop section, :any, default: nil
  prop setting_boundaries, :boolean, default: false
  prop scope, :any, default: :user
  prop usage, :any, default: :all

  def update(assigns, %{assigns: %{loaded: true}} = socket) do
    params = e(assigns, :__context__, :current_params, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(section: e(params, "section", "permissions"))}
  end

  def update(assigns, socket) do
    current_user = current_user(assigns)
    params = e(assigns, :__context__, :current_params, %{})

    acl_id = e(assigns, :acl_id, nil) || e(socket.assigns, :acl_id, nil) || e(params, "id", nil)
    scope = e(assigns, :scope, nil) || e(socket.assigns, :scope, nil)

    scope_type = Types.object_type(scope) || scope

    # note: Verbs only needed if doing custom permissions rather than using roles
    # verbs = Bonfire.Boundaries.Verbs.list(:db, :id)
    # verbs =
    #   if scope != :instance do
    #     # filter out instance-related roles (to show only content related ones)
    #
    #     instance_verbs =
    #       Bonfire.Boundaries.Verbs.list(:instance, :id)
    #       |> debug

    #     verbs
    #     |> Enum.reject(&(elem(&1, 0) in instance_verbs))
    #     |> debug
    #   else
    #     verbs
    #   end

    global_circles = Bonfire.Boundaries.Fixtures.global_circles()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       scope_type: scope_type,
       section: e(params, "section", "permissions"),
       #  verbs: verbs,
       acl_id: acl_id,
       #  suggestions: suggestions,
       global_circles: global_circles,
       my_circles:
         Bonfire.Boundaries.Web.SetBoundariesLive.list_my_circles(
           if is_nil(scope) or scope == :user, do: current_user, else: scope
         )
         |> Bonfire.Boundaries.Web.SetBoundariesLive.results_for_multiselect(),
       settings_section_title: "View boundary",
       settings_section_description: l("Create and manage your boundary."),
       selected_tab: "acls"
     )
     |> assign_updated()}
  end

  def assign_updated(socket, force? \\ false) do
    current_user = current_user(socket)

    acl_id = e(socket.assigns, :acl_id, nil)
    acl = e(socket.assigns, :acl, nil)
    acl = if id(acl) == acl_id, do: {:ok, acl}

    with {:ok, acl} <-
           (acl || Acls.get_for_caretaker(acl_id, current_user))
           |> repo().maybe_preload(
             [
               grants: [
                 :verb,
                 subject: [:named, :profile, :character, stereotyped: [:named]]
               ]
             ],
             force: force?
           ) do
      debug(acl, "acllll")

      if e(socket.assigns, :scope_type, nil) not in [:group, Bonfire.Classify.Category] do
        send_self(
          back: true,
          page_title: e(acl, :named, :name, nil) || e(acl, :stereotyped, :named, :name, nil),
          acl: acl,
          page_header_aside: []
        )
      end

      # verbs = e(socket.assigns, :verbs, [])

      feed_by_subject = Grants.subject_verb_grants(e(acl, :grants, []))
      # list_by_verb = verb_subject_grant(e(acl, :grants, []))

      socket
      |> assign(
        loaded: true,
        settings_section_title: "View " <> e(acl, :named, :name, "") <> " boundary",
        acl: acl,
        feed_by_subject: feed_by_subject,
        # list_by_verb: Map.merge(verbs, list_by_verb),
        # subjects: subjects(e(acl, :grants, [])),
        read_only:
          Acls.is_stereotype?(acl) or
            (!Acls.is_object_custom?(acl) and
               (Acls.is_stereotyped?(acl) and
                  !Bonfire.Boundaries.can?(current_user, :grant, :instance)))
      )
    end
  end

  def do_handle_event("edit", attrs, socket) do
    debug(attrs)

    with {:ok, acl} <-
           Acls.edit(e(socket.assigns, :acl, nil), current_user_required!(socket), attrs) do
      {:noreply,
       socket
       |> assign_flash(:info, l("Edited!"))
       |> assign(acl: acl)}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not edit boundary"))}
    end
  end

  def do_handle_event("add_to_acl", %{"id" => id} = _attrs, socket) do
    add_to_acl(id, socket)
  end

  def do_handle_event("remove_from_acl", %{"subject_id" => subject}, socket) do
    remove_from_acl(subject, socket)
  end

  def do_handle_event("tagify_remove", %{"id" => subject} = _attrs, socket) do
    remove_from_acl(subject, socket)
  end

  def do_handle_event("tagify_add", %{"id" => id} = _attrs, socket) do
    add_to_acl(id, socket)
  end

  def do_handle_event("select", %{"id" => id} = _attrs, socket) do
    add_to_acl(id, socket)
  end

  def do_handle_event("multi_select", %{data: data, text: text}, socket) do
    add_to_acl(data, socket)
  end

  def do_handle_event("edit_verb_value", %{"subject" => subjects} = _attrs, socket) do
    # debug(attrs)
    current_user = current_user_required!(socket)
    acl = e(socket.assigns, :acl, nil)
    # verb_value = List.first(Map.values(subjects))
    grant =
      Enum.flat_map(subjects, fn {subject_id, verb_value} ->
        Enum.flat_map(verb_value, fn {verb, value} ->
          debug(acl, "#{subject_id} -- #{verb} = #{value}")

          [
            Grants.grant(subject_id, acl, verb, value, current_user: current_user)
          ]
        end)
      end)

    # |> debug("done")
    with [ok: grant] <- grant do
      debug(grant)

      {
        :noreply,
        socket
        |> assign_flash(:info, l("Permission edited!"))
        |> assign_updated(true)

        # |> assign(
        # list: Map.merge(e(socket.assigns, :list, %{}), %{id=> %{subject: %{name: e(socket.assigns, :suggestions, id, nil)}}}) #|> debug
        # )
      }
    else
      other ->
        error(other)

        {:noreply, assign_error(socket, l("Could not edit permission"))}
    end
  end

  def do_handle_event("edit_grant_role", %{"to_circles" => subjects} = _attrs, socket) do
    # debug(attrs)
    current_user = current_user_required!(socket)
    acl = e(socket.assigns, :acl, nil)
    scope = e(socket.assigns, :scope, nil)

    grants =
      Enum.map(subjects, fn {subject_id, role_name} ->
        Grants.grant_role(subject_id, acl, role_name, current_user: current_user, scope: scope)
      end)
      |> List.flatten()

    # |> debug("done")

    with [:ok] <- Keyword.keys(grants) |> Enum.uniq() do
      {
        :noreply,
        socket
        |> assign_flash(:info, l("Role assigned!"))
        |> assign_updated(true)
        # |> assign(
        # list: Map.merge(e(socket.assigns, :list, %{}), %{id=> %{subject: %{name: e(socket.assigns, :suggestions, id, nil)}}}) #|> debug
        # )
      }
    else
      other ->
        error(other)

        {:noreply, assign_error(socket, l("Could not assign the role"))}
    end
  end

  def do_handle_event("edit_circle", %{"id" => id}, socket) do
    debug(id, "circle_edit")

    {:noreply, assign(socket, :edit_circle_id, id)}
  end

  # TODO
  def do_handle_event("back", _, socket) do
    {:noreply,
     assign(
       socket,
       edit_circle_id: nil,
       section: nil
     )}
  end

  def do_handle_event(
        "live_select_change",
        %{"id" => live_select_id, "text" => search},
        %{assigns: %{scope: :user}} = socket
      ) do
    current_user = current_user(socket)

    (Bonfire.Boundaries.Circles.list_my_with_global(
       [current_user, Bonfire.Boundaries.Fixtures.activity_pub_circle()],
       search: search
     ) ++
       Bonfire.Me.Users.search(search))
    |> results_for_multiselect(live_select_id, socket)
  end

  def do_handle_event(
        "live_select_change",
        %{"id" => live_select_id, "text" => search},
        %{assigns: %{scope: :instance}} = socket
      ) do
    (Bonfire.Boundaries.Circles.list_my_with_global(
       [
         Bonfire.Boundaries.Fixtures.admin_circle(),
         Bonfire.Boundaries.Fixtures.activity_pub_circle()
       ],
       search: search
     ) ++
       Bonfire.Me.Users.search(search))
    |> results_for_multiselect(live_select_id, socket)
  end

  def do_handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket) do
    current_user = current_user(socket)
    # for groups and the like 
    # TODO: should they have their own circles?
    (Bonfire.Boundaries.Circles.list_my_with_global(
       [Bonfire.Boundaries.Fixtures.activity_pub_circle()],
       search: search
     ) ++
       Bonfire.Me.Users.search(search))
    |> results_for_multiselect(live_select_id, socket)
  end

  defp results_for_multiselect(results, live_select_id, socket) do
    results
    |> Bonfire.Boundaries.Web.SetBoundariesLive.results_for_multiselect()
    |> maybe_send_update(LiveSelect.Component, live_select_id, options: ...)

    {:noreply, socket}
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

  def add_to_acl(id, socket) when is_binary(id) do
    {:noreply,
     do_add_to_acl(
       %{
         id: id,
         name: e(socket.assigns, :suggestions, id, nil)
       },
       socket
     )}
  end

  def add_to_acl(subject, socket) do
    {:noreply, do_add_to_acl(subject, socket)}
  end

  defp do_add_to_acl(subject, socket) do
    id = ulid(subject)
    # |> debug("id")

    subject_map = %{id => %{subject: subject, grants: nil}}

    # subject_name = LiveHandler.subject_name(subject)
    # |> debug("name")

    socket
    |> assign(
      # subjects: ([subject] ++ e(socket.assigns, :subjects, [])) |> Enum.uniq_by(&ulid/1),
      # so tagify doesn't remove it as invalid
      # suggestions: Map.put(e(socket.assigns, :suggestions, %{}), id, subject_name),
      feed_by_subject: e(socket.assigns, :feed_by_subject, %{}) |> Map.merge(subject_map)
      # list_by_verb:
      #   e(socket.assigns, :list_by_verb, %{})
      #   |> Enum.map(fn
      #     {verb_id, %{verb: verb, subject_verb_grants: subject_verb_grants}} ->
      #       {
      #         verb_id,
      #         %{
      #           verb: verb,
      #           subject_verb_grants: Map.merge(subject_verb_grants, subject_map)
      #         }
      #       }

      #     {verb_id, %Bonfire.Data.AccessControl.Verb{} = verb} ->
      #       {
      #         verb_id,
      #         %{
      #           verb: verb,
      #           subject_verb_grants: subject_map
      #         }
      #       }
      #   end)
      #   # |> debug
      #   |> Map.new()

      # list: Map.merge(e(socket.assigns, :list, %{}), %{id=> %{subject: %{name: e(socket.assigns, :suggestions, id, nil)}}}) #|> debug
    )
    |> assign_flash(
      :info,
      l("Select a role (or custom permissions) to finish adding it to the boundary.")
    )

    # |> assign_updated()
  end

  def remove_from_acl(subject, socket) do
    # IO.inspect(subject, label: "ULLID")
    acl_id = ulid!(e(socket.assigns, :acl, nil))
    # subject_id = ulid!(subject)

    {:noreply,
     with {del, _} when is_integer(del) and del > 0 <-
            Grants.remove_subject_from_acl(subject, acl_id) do
       assign_flash(socket, :info, l("Removed from boundary"))
       |> assign_updated(true)

       # |> redirect_to(~p"/boundaries/acl/#{id}")
     else
       _ ->
         assign_flash(socket, :info, l("No permissions removed from boundary"))
     end}
  end

  def can(grants) do
    grants
    |> Enum.filter(fn {_, grant} -> e(grant, :value, nil) == true end)
    |> Enum.map(fn {_, grant} ->
      e(grant, :verb, :verb, nil) || e(grant, :verb, nil)
    end)

    # |> maybe_join(l "Can")
  end

  def cannot(grants) do
    grants
    # |> debug
    |> Enum.filter(fn {_, grant} ->
      is_map(grant) and Map.get(grant, :value, nil) == false
    end)
    |> Enum.map(fn {_, grant} ->
      e(grant, :verb, :verb, nil) || e(grant, :verb, nil)
    end)

    # |> maybe_join(l "Cannot")
  end

  def maybe_join(list, prefix) when is_list(list) and length(list) > 0 do
    prefix <> ": " <> Enum.join(list, ", ")
  end

  def maybe_join(_, _) do
    nil
  end

  # def columns(context) do
  #  if context[:ui_compact], do: 3, else: 2
  # end

  def predefined_subjects(subjects) do
    Enum.map(subjects, fn s ->
      %{"value" => ulid(s), "text" => LiveHandler.subject_name(s) || ulid(s)}
    end)
    # |> Enum.join(", ")
    |> Jason.encode!()

    # |> debug()
    # [{"value":"good", "text":"The Good, the Bad and the Ugly"}, {"value":"matrix", "text":"The Matrix"}]
  end
end
