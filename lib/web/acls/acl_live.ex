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

    {:ok, socket
      |> assign(assigns)
      |> assign(
        section: e(params, "section", "permissions")
      )
    }
  end

  def update(assigns, socket) do
    current_user = current_user(assigns)
    params = e(assigns, :__context__, :current_params, %{})

    id = e(assigns, :acl_id, nil) || e(params, "id", nil)
    # |> debug

    with {:ok, acl} <- Acls.get_for_caretaker(id, current_user) |> repo().maybe_preload(grants: [:verb, subject: [:named, :profile, :character, stereotyped: [:named]]]) do
      # debug(acl, "acl")

      verbs = Bonfire.Boundaries.Verbs.list(:db, :id)

      # list = subject_verb_grant(e(acl, :grants, []))
      list = verb_subject_grant(e(acl, :grants, []))

      # # TODO: handle pagination?
      followed = Bonfire.Social.Follows.list_my_followed(current_user, paginate: false)

      already_seen_ids = Enum.map(followed, & &1.edge.object_id)
      # # |> debug
      followers = Bonfire.Social.Follows.list_my_followers(current_user, paginate: false, exclude_ids: already_seen_ids)
      # |> debug

      global_circles = Bonfire.Boundaries.Fixtures.global_circles

      circles = Bonfire.Boundaries.Circles.list_my(current_user, extra_ids_to_include: global_circles)

      extra_circles = if Integration.is_admin?(current_user) || Bonfire.Boundaries.can?(current_user, :grant, :instance), do: Bonfire.Boundaries.Circles.list_my(Bonfire.Boundaries.Fixtures.admin_circle), else: []

      suggestions = (for user <- followed ++ followers do
        {e(user, :edge, :object, :id, nil), e(user, :edge, :object, :profile, :name, "")<>" - "<>Bonfire.Me.Characters.display_username(e(user, :edge, :object, nil))}
      end
      ++
      for circle <- circles ++ extra_circles do
        {ulid(circle), (e(circle, :named, :name, nil) || e(circle, :stereotyped, :named, :name, nil) || l "Untitled circle") }
      end)
      |> Map.new
      # |> debug

      {:ok, socket
      |> assign(assigns)
      |> assign(
        loaded: true,
        section: e(params, "section", "permissions"),
        # verbs: verbs,
        acl: acl,
        list: Map.merge(verbs, list),
        subjects: subjects(e(acl, :grants, [])),
        suggestions: suggestions,
        global_circles: global_circles,
        read_only: Acls.is_stereotype?(acl) or ( ulid(acl) in Acls.built_in_ids() and !Bonfire.Boundaries.can?(current_user, :grant, :instance)),
        settings_section_title: "View " <> e(acl, :named, :name, "") <> " boundary",
        settings_section_description: l("Create and manage your boundary."),
        ui_compact: Settings.get([:ui, :compact], false, assigns),
        sidebar_widgets: [
          users: [
            main: [
              {Bonfire.UI.Me.SettingsViewLive.SidebarSettingsLive,
              [
                selected_tab: "acls",
                current_user: current_user(assigns)
              ]}
            ],
            secondary: []
          ]
        ]
      )}
    end
  end

  def handle_event("edit", attrs, socket) do
    debug(attrs)
    with {:ok, acl} <-  Acls.edit(e(socket.assigns, :acl, nil), current_user(socket), attrs) do
      {:noreply, socket
        |> assign_flash(:info, l "Edited!")
        |> assign(acl: acl)
      }
    else other ->
      error(other)
      {:noreply, socket
        |> assign_flash(:error, l "Could not edit boundary")
      }
    end
  end


  def handle_event("tagify_remove", %{"id" => subject} = _attrs, socket) do
    Bonfire.Boundaries.LiveHandler.remove_from_acl(subject, socket)
  end

  def handle_event("tagify_add", %{"id" => id} = _attrs, socket) do
    Bonfire.Boundaries.LiveHandler.add_to_acl(id, socket)
  end

  def handle_event("edit_grant", attrs, socket) do
    # debug(attrs)
    current_user = current_user(socket)
    edit_grant = e(attrs, "subject", nil)
    acl = e(socket.assigns, :acl, nil)
    # verb_value = List.first(Map.values(edit_grant))
    grant = Enum.flat_map(edit_grant, fn {subject_id, verb_value} ->
      Enum.flat_map(verb_value, fn {verb, value} ->
        debug(acl, "#{subject_id} -- #{verb} = #{value}")
        [Grants.grant(subject_id, acl, verb, value, current_user: current_user)]
      end)
    end)
    # |> debug("done")
    with [ok: grant] <- grant do
      debug(grant)
      {:noreply, socket
          |> assign_flash(:info, l "Permission edited!")
        # |> assign(
          # list: Map.merge(e(socket.assigns, :list, %{}), %{id=> %{subject: %{name: e(socket.assigns, :suggestions, id, nil)}}}) #|> debug
        # )
      }
    else other ->
      error(other)
      {:noreply, socket
        |> assign_flash(:error, l "Could not edit permission")
      }
    end
  end

  def handle_event("edit_circle", %{"id"=> id}, socket) do
    debug(id, "circle_edit")
    {:noreply, socket
      |> assign(:edit_circle_id, id)
    }
  end

  def handle_event("back", _, socket) do # TODO
    {:noreply, socket
      |> assign(
        edit_circle_id: nil,
        section: nil
      )
    }
  end

  def handle_event(action, attrs, socket), do: Bonfire.UI.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)

  def can(grants) do
    grants
    |> Enum.filter(fn {_, grant} -> e(grant, :value, nil)==true end)
    |> Enum.map(fn {_, grant} -> e(grant, :verb, :verb, nil) || e(grant, :verb, nil) end)
    # |> maybe_join(l "Can")
  end

  def cannot(grants) do
    grants
    # |> debug
    |> Enum.filter(fn {_, grant} -> is_map(grant) and Map.get(grant, :value, nil)==false end)
    |> Enum.map(fn {_, grant} -> e(grant, :verb, :verb, nil) || e(grant, :verb, nil) end)
    # |> maybe_join(l "Cannot")
  end

  def maybe_join(list, prefix) when is_list(list) and length(list)>0 do
    prefix<>": "<> Enum.join(list, ", ")
  end
  def maybe_join(_, _) do
    nil
  end

  def subjects(grants) when is_list(grants) and length(grants)>0 do
    # TODO: rewrite this whole thing tbh
    Enum.reduce(grants, [], fn grant, subjects_acc ->
      subjects_acc ++ [grant.subject]
    end)
    |> Enum.uniq()
    # |> debug
  end

  def subjects(_), do: %{}


  def subject_verb_grant(grants) when is_list(grants) and length(grants)>0 do
    # TODO: rewrite this whole thing tbh
    Enum.reduce(grants, %{}, fn grant, subjects_acc ->
      new_grant = %{grant.verb_id => Map.drop(grant, [:subject])}
      new_subject = %{subject: grant.subject, verb_grants: new_grant}
      Map.update(subjects_acc,
        grant.subject_id, # key
        new_subject, # first entry
        fn existing_subject ->
          Map.update(existing_subject,
          :verb_grants, # key
          new_grant, # first entry
          fn existing_grants ->
            Map.merge(existing_grants, new_grant)
          end)
      end)
    end)
    # |> debug
  end

  def subject_verb_grant(_), do: %{}


  def verb_subject_grant(grants) when is_list(grants) and length(grants)>0 do
    # TODO: rewrite this whole thing tbh
    Enum.reduce(grants, %{}, fn grant, verbs_acc ->
      new_grant = %{grant.subject_id => Map.drop(grant, [:verb])}
      new_verb = %{verb: grant.verb, subject_grants: new_grant}
      Map.update(verbs_acc,
        grant.verb_id, # key
        new_verb, # first entry
        fn existing_verb ->
          Map.update(existing_verb,
          :subject_grants, # key
          new_grant, # first entry
          fn existing_grants ->
            Map.merge(existing_grants, new_grant)
          end)
      end)
    end)
    # |> debug
  end

  def verb_subject_grant(_), do: %{}


  def columns(context) do
    # if Settings.get([:ui, :compact], false, context), do: 3, else: 2
    2
  end

  def predefined_subjects(subjects) do
    Enum.map(subjects, fn s -> %{"value"=> ulid(s), "text"=> LiveHandler.subject_name(s) || ulid(s)} end)
    # |> Enum.join(", ")
    |> Jason.encode!()
    # |> debug()
    # [{"value":"good", "text":"The Good, the Bad and the Ugly"}, {"value":"matrix", "text":"The Matrix"}]
  end
end
