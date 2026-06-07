defmodule Bonfire.Boundaries.VerbGrants do
  @moduledoc """
  Context module for transforming verb-level permissions between internal and API formats.
  Lives in bonfire_boundaries (not bonfire_ui_boundaries) so it can be called from
  both UI components and the GraphQL/REST API layer.
  """

  use Bonfire.Common.Utils

  @doc """
  Transforms the internal verb permissions format to direct verb grants, bypassing the role system.

  Takes a map like:
  `%{"like" => %{"circle_id_1" => :can, "circle_id_2" => :cannot}, "boost" => %{"circle_id_1" => :can}}`

  Returns a flat list of `{circle_id, verb_atom, boolean}` triples.
  """
  def transform_to_verb_grants_format(verb_permissions) do
    verb_permissions
    |> Enum.flat_map(fn {verb, circle_perms} ->
      verb_atom = maybe_to_atom(verb)

      Enum.flat_map(circle_perms, fn {circle_id, permission} ->
        value =
          case permission do
            :can -> true
            "can" -> true
            :cannot -> false
            "cannot" -> false
            _ -> nil
          end

        if value != nil, do: [{circle_id, verb_atom, value}], else: []
      end)
    end)
  end

  @doc """
  Transforms ACL subject verb grants to verb permissions format for display.

  Takes ACL grants structure:
  `%{subject_id => %{subject: subject, grants: %{verb_id => grant}}}`

  Returns `{verb_permissions, to_circles}`.
  """
  def transform_acl_to_verb_format(acl_subject_verb_grants) do
    debug(acl_subject_verb_grants, "Input to transform_acl_to_verb_format")

    verb_permissions =
      Enum.reduce(acl_subject_verb_grants, %{}, fn {subject_id, %{grants: grants}}, acc ->
        debug({subject_id, Map.keys(grants || %{})}, "Processing subject grants")

        Enum.reduce(grants || %{}, acc, fn {verb_id, grant}, verb_acc ->
          raw_verb_name = e(grant, :verb, :verb, nil)
          debug({verb_id, raw_verb_name, grant}, "Verb debugging info")

          verb_name =
            case raw_verb_name do
              name when is_binary(name) -> String.downcase(name)
              _ -> to_string(verb_id)
            end

          value =
            case e(grant, :value, nil) do
              true -> :can
              false -> :cannot
              nil -> nil
            end

          debug({verb_name, value, subject_id}, "Creating verb permission with name")

          current_verb_map = Map.get(verb_acc, verb_name, %{})
          Map.put(verb_acc, verb_name, Map.put(current_verb_map, subject_id, value))
        end)
      end)

    debug(verb_permissions, "Final verb_permissions from transform")

    to_circles =
      Enum.map(acl_subject_verb_grants, fn {_id, %{subject: subject}} ->
        {subject, nil}
      end)

    {verb_permissions, to_circles}
  end

  @doc """
  Reconstructs verb_permissions map from to_circles and exclude_circles lists.

  This is the reverse of transform_to_circles_format/1, used to restore state
  when components are recreated (e.g., modal reopening).
  """
  def reconstruct_verb_permissions(to_circles, exclude_circles) do
    verb_permissions = %{}

    # Process to_circles (both positive and negative permissions)
    verb_permissions =
      Enum.reduce(to_circles || [], verb_permissions, fn {circle, verbs}, acc ->
        circle_id = id(circle)

        # Parse verbs (handle both string and list formats)
        verb_list =
          case verbs do
            verbs_string when is_binary(verbs_string) ->
              if verbs_string == "", do: [], else: String.split(verbs_string, ",")

            verb_list when is_list(verb_list) ->
              Enum.map(verb_list, &to_string/1)

            single_verb ->
              [to_string(single_verb)]
          end

        # Process each verb, handling both positive and negative permissions
        # Note: Negative permissions come as individual "cannot_verb" entries, not comma-separated
        Enum.reduce(verb_list, acc, fn verb, verb_acc ->
          verb_string = to_string(verb)

          # Check if this is a negative permission (starts with "cannot_")
          if String.starts_with?(verb_string, "cannot_") do
            # Extract the actual verb name by removing "cannot_" prefix
            actual_verb = String.replace_prefix(verb_string, "cannot_", "")
            current_verb_map = Map.get(verb_acc, actual_verb, %{})
            Map.put(verb_acc, actual_verb, Map.put(current_verb_map, circle_id, :cannot))
          else
            # Positive permission (can be comma-separated for efficiency)
            current_verb_map = Map.get(verb_acc, verb_string, %{})
            Map.put(verb_acc, verb_string, Map.put(current_verb_map, circle_id, :can))
          end
        end)
      end)

    # Note: exclude_circles processing is now handled above in the to_circles processing
    # since we encode negative permissions as "cannot_verb" in to_circles

    verb_permissions
  end

  @doc """
  Updates a single verb permission for a specific circle.
  """
  def update_verb_permission(current_permissions, circle_id, verb, verb_value) do
    current_permissions
    |> Map.put(verb, Map.put(Map.get(current_permissions, verb, %{}), circle_id, verb_value))
  end
end
