defmodule Bonfire.Boundaries.Web.AclLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Grants
  require Integer

  prop acl_id, :any
  prop parent_back, :any
  prop columns, :integer, default: 3

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

    with {:ok, acl} <- Bonfire.Boundaries.Acls.get_for_caretaker(id, current_user) |> repo().maybe_preload(grants: [:verb, subject: [:named, :profile, :character, stereotyped: [:named]]]) do
      debug(acl, "acl")

      verbs = Bonfire.Boundaries.Verbs.list(:db, :id)

      # list = subject_verb_grant(e(acl, :grants, []))
      list = verb_subject_grant(e(acl, :grants, []))

      already_set_ids = Map.keys(list)

      # # TODO: handle pagination?
      followed = Bonfire.Social.Follows.list_my_followed(current_user, paginate: false, exclude_ids: already_set_ids)

      already_seen_ids = already_set_ids ++ Enum.map(followed, & &1.edge.object_id)
      # # |> debug
      followers = Bonfire.Social.Follows.list_my_followers(current_user, paginate: false, exclude_ids: already_seen_ids)
      # |> debug

      circles = Bonfire.Boundaries.Circles.list_my(current_user, extra_ids_to_include: ["0AND0MSTRANGERS0FF1NTERNET", "3SERSFR0MY0VR10CA11NSTANCE", "7EDERATEDW1THANACT1V1TYPVB"])

      suggestions = (for user <- followed ++ followers do
        {e(user, :edge, :object, :id, nil), e(user, :edge, :object, :profile, :name, "")<>" - "<>Bonfire.Me.Characters.display_username(e(user, :edge, :object, nil))}
      end
      ++
      for circle <- circles do
        {e(circle, :id, nil), (e(circle, :named, :name, nil) || e(circle, :stereotyped, :named, :name, nil) || l "Untitled")<>" "<> l "(circle)" }
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
        read_only: e(acl, :stereotyped, :stereotype_id, nil) || acl.id in Bonfire.Boundaries.Acls.built_in_ids,
        settings_section_title: "View " <> e(acl, :named, :name, "acl name") <> " boundary",
        settings_section_description: l "Create and manage your boundary."
      )}
    end
  end

  def handle_event("add", attrs, socket) do
    debug(attrs)
    id = e(attrs, "add", nil)
    subject = %{id: id, name: e(socket.assigns, :suggestions, id, nil)}
    subject_map = %{id=> %{subject: subject}}
    {:noreply, socket
      |> assign(
        subjects: e(socket.assigns, :subjects, []) ++ [subject],
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
    }
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
          |> assign_flash(:info, "Permission edited")
        # |> assign(
          # list: Map.merge(e(socket.assigns, :list, %{}), %{id=> %{subject: %{name: e(socket.assigns, :suggestions, id, nil)}}}) #|> debug
        # )
      }
    else other ->
      error(other)
      {:noreply, socket
        |> assign_flash(:error, "Could not edit permission")
      }
    end
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

end
