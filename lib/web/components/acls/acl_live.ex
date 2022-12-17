defmodule Bonfire.Boundaries.Web.AclLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Grants
  alias Bonfire.Boundaries.LiveHandler
  alias Bonfire.Boundaries.Integration
  require Integer

  prop acl_id, :string, default: nil
  prop edit_circle_id, :string, default: nil
  prop parent_back, :any, default: nil
  prop columns, :integer, default: 1
  prop selected_tab, :any, default: nil
  prop section, :any, default: nil
  prop setting_boundaries, :boolean, default: false
  prop scope, :atom, default: nil

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

    verbs = Bonfire.Boundaries.Verbs.list(:db, :id)

    global_circles = Bonfire.Boundaries.Fixtures.global_circles()

    # circles =
    #   Bonfire.Boundaries.Circles.list_my_with_global(current_user,
    #     global_circles: global_circles
    #   )

    # extra_circles =
    #   if Integration.is_admin?(current_user) ||
    #        Bonfire.Boundaries.can?(current_user, :grant, :instance),
    #      do: Bonfire.Boundaries.Circles.list_my(Bonfire.Boundaries.Fixtures.admin_circle()),
    #      else: []

    # # TODO: handle pagination?
    # followed = Bonfire.Social.Follows.list_my_followed(current_user, paginate: false)
    # already_seen_ids = Enum.map(followed, & &1.edge.object_id)
    # followers =
    #   Bonfire.Social.Follows.list_my_followers(current_user,
    #     paginate: false,
    #     exclude_ids: already_seen_ids
    #   )

    # suggestions =
    #   (for user <- followed ++ followers do
    #      {e(user, :edge, :object, :id, nil),
    #       e(user, :edge, :object, :profile, :name, "") <>
    #         " - " <>
    #         Bonfire.Me.Characters.display_username(e(user, :edge, :object, nil))}
    #    end ++
    #      for circle <- circles ++ extra_circles do
    #        {ulid(circle),
    #         e(circle, :named, :name, nil) ||
    #           e(circle, :stereotyped, :named, :name, nil) ||
    #           l("Untitled circle")}
    #      end)
    #   |> Map.new()

    # |> debug

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       section: e(params, "section", "permissions"),
       verbs: verbs,
       acl_id: acl_id,
       #  suggestions: suggestions,
       global_circles: global_circles,
       settings_section_title: "View boundary",
       settings_section_description: l("Create and manage your boundary."),
       ui_compact: Settings.get([:ui, :compact], false, assigns),
       selected_tab: "acls"
     )
     |> assign_updated_grants()}
  end

  def assign_updated_grants(socket) do
    current_user = current_user(socket)

    acl_id = e(socket.assigns, :acl_id, nil)

    with {:ok, acl} <-
           Acls.get_for_caretaker(acl_id, current_user)
           |> repo().maybe_preload(
             grants: [
               :verb,
               subject: [:named, :profile, :character, stereotyped: [:named]]
             ]
           ) do
      # debug(acl, "acl")

      verbs = e(socket.assigns, :verbs, [])

      list_by_subject = subject_verb_grant(e(acl, :grants, []))
      list_by_verb = verb_subject_grant(e(acl, :grants, []))

      socket
      |> assign(
        loaded: true,
        settings_section_title: "View " <> e(acl, :named, :name, "") <> " boundary",
        acl: acl,
        list_by_subject: list_by_subject,
        list_by_verb: Map.merge(verbs, list_by_verb),
        subjects: subjects(e(acl, :grants, [])),
        read_only:
          Acls.is_stereotype?(acl) or
            (acl_id in Acls.built_in_ids() and
               !Bonfire.Boundaries.can?(current_user, :grant, :instance))
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

  def do_handle_event("tagify_remove", %{"id" => subject} = _attrs, socket) do
    Bonfire.Boundaries.LiveHandler.remove_from_acl(subject, socket)
  end

  def do_handle_event("tagify_add", %{"id" => id} = _attrs, socket) do
    Bonfire.Boundaries.LiveHandler.add_to_acl(id, socket)
  end

  def do_handle_event("edit_grant_verb", %{"subject" => subjects} = attrs, socket) do
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
        |> assign_updated_grants()

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

  def do_handle_event("edit_grant_role", %{"to_circles" => subjects} = attrs, socket) do
    # debug(attrs)
    current_user = current_user_required!(socket)
    acl = e(socket.assigns, :acl, nil)

    grants =
      Enum.flat_map(subjects, fn {subject_id, role_name} ->
        Grants.grant_role(subject_id, acl, role_name, current_user: current_user)
      end)
      |> debug("done")

    with [:ok] <- Keyword.keys(grants) |> Enum.uniq() |> debug("done") do
      {
        :noreply,
        socket
        |> assign_flash(:info, l("Permission edited!"))
        |> assign_updated_grants()
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

  def subjects(grants) when is_list(grants) and length(grants) > 0 do
    # TODO: rewrite this whole thing tbh
    Enum.reduce(grants, [], fn grant, subjects_acc ->
      subjects_acc ++ [grant.subject]
    end)
    |> Enum.uniq()
  end

  def subjects(_), do: %{}

  def subject_verb_grant(grants) when is_list(grants) and length(grants) > 0 do
    # TODO: rewrite this whole thing tbh
    Enum.reduce(grants, %{}, fn grant, subjects_acc ->
      new_grant = %{grant.verb_id => Map.drop(grant, [:subject])}
      new_subject = %{subject: grant.subject, verb_grants: new_grant}

      Map.update(
        subjects_acc,
        # key
        grant.subject_id,
        # first entry
        new_subject,
        fn existing_subject ->
          Map.update(
            existing_subject,
            # key
            :verb_grants,
            # first entry
            new_grant,
            fn existing_grants ->
              Map.merge(existing_grants, new_grant)
            end
          )
        end
      )
    end)
    |> debug
  end

  def subject_verb_grant(_), do: %{}

  def verb_subject_grant(grants) when is_list(grants) and length(grants) > 0 do
    # TODO: rewrite this whole thing tbh
    Enum.reduce(grants, %{}, fn grant, verbs_acc ->
      new_grant = %{grant.subject_id => Map.drop(grant, [:verb])}
      new_verb = %{verb: grant.verb, subject_grants: new_grant}

      Map.update(
        verbs_acc,
        # key
        grant.verb_id,
        # first entry
        new_verb,
        fn existing_verb ->
          Map.update(
            existing_verb,
            # key
            :subject_grants,
            # first entry
            new_grant,
            fn existing_grants ->
              Map.merge(existing_grants, new_grant)
            end
          )
        end
      )
    end)

    # |> debug
  end

  def verb_subject_grant(_), do: %{}

  def columns(context) do
    # if Settings.get([:ui, :compact], false, context), do: 3, else: 2
    2
  end

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
