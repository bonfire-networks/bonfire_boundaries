defmodule Bonfire.Boundaries.Roles do
  use Bonfire.Common.Utils
  import Untangle
  import Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.Verbs

  def role_verbs(usage \\ nil, opts \\ [])
  def role_verbs(:ops, opts), do: Settings.get(:role_verbs, [], opts)

  def role_verbs(_, opts),
    do:
      Settings.get(:role_verbs, [], opts)
      |> Enums.fun(:filter, fn
        %{usage: :ops} -> false
        _ -> true
      end)

  def get(role_name, opts) do
    Settings.get([:role_verbs, role_name], %{}, opts)
    |> Enum.into(%{})
    |> debug(role_name)
  end

  # def negative_role_verbs(usage \\ nil)
  # def negative_role_verbs(:ops), do: Config.get(:negative_role_verbs)
  # def negative_role_verbs(_),
  #   do:
  #     Config.get(:negative_role_verbs)
  #     |> Enums.fun(:filter, fn
  #       %{usage: :ops} -> false
  #       _ -> true
  #     end)

  def roles_for_dropdown(usage \\ nil, opts) do
    roles = role_verbs(usage, opts) |> Enums.fun(:keys)

    # negative =
    #   negative_role_verbs(usage)
    #   |> Enums.fun(:keys)
    #   |> debug()

    debug(
      for role <- roles || [] do
        {role, String.capitalize(to_string(role))}
      end
    )

    # ++
    #   debug(
    #     for role <- negative || [] do
    #       {"negative_#{role}", l("Cannot") <> " " <> String.capitalize(to_string(role))}
    #     end
    #   )
  end

  defp role_from_verb_names(verbs) do
    role_from_verb(verbs, :verb) || :custom
  end

  def role_from_grants(grants) do
    {positive, negative} =
      Enum.split_with(grants, fn
        %{value: value} -> value
      end)
      |> debug("good vs evil")

    cond do
      positive != [] and negative == [] ->
        role_from_verb(verb_ids_from_grants(positive), :id)

      positive == [] and negative != [] ->
        negative_role_from_verb(verb_ids_from_grants(negative), :id)

      true ->
        nil
    end || :custom
  end

  defp verb_ids_from_grants(grants) do
    Enum.map(grants, &e(&1, :verb_id, nil))
  end

  def negative_role_from_verb(
        verbs,
        field \\ :verb,
        all_role_verbs \\ role_verbs(),
        role_for_all \\ :read,
        field \\ :cannot_verbs
      ) do
    "negative_#{role_from_verb(verbs, field, all_role_verbs, role_for_all, field) || :none}"
  end

  def role_from_verb(
        verbs,
        verb_field \\ :verb,
        all_role_verbs \\ role_verbs(),
        role_for_all \\ :administer,
        verbs_field \\ :can_verbs
      ) do
    cond do
      Enum.count(verbs) == Verbs.verbs_count() ->
        role_for_all

      true ->
        case all_role_verbs
             |> debug("all_role_verbs")
             |> Enum.filter(fn {_role, %{^verbs_field => a_role_verbs}} ->
               verbs ==
                 Enum.map(a_role_verbs, &Map.get(Verbs.get(&1), verb_field))
                 |> Enum.sort()

               # |> debug
             end) do
          [{role, _verbs}] ->
            role

          other ->
            warn(other, "unknown")
            nil
        end
    end
    |> debug()
  end

  def verbs_for_role(role, opts)

  def verbs_for_role("negative_" <> role, opts) do
    do_verbs_for_role(role, false, :cannot_verbs, role_verbs(nil, opts))
  end

  def verbs_for_role(role, opts) do
    do_verbs_for_role(role, true, :can_verbs, role_verbs(nil, opts))
  end

  defp do_verbs_for_role(role, value, field, all_role_verbs) do
    role =
      role
      |> Types.maybe_to_atom()
      |> debug("role")

    if is_atom(role) do
      roles = role_verbs |> Enums.fun(:keys)

      cond do
        role in roles ->
          {:ok, value, e(role_verbs, role, field, [])}

        role in [nil, :none, :custom] ->
          {:ok, value, []}

        true ->
          debug(roles, "available roles")
          error(role, "This role is not defined.")
      end
    else
      error(role, "This is not a valid role.")
    end
  end

  def preset_boundary_role_from_acl(%{verbs: verbs} = _summary) do
    # debug(summary)
    case role_from_verb_names(verbs) do
      :administer -> {l("Administer"), l("Full permissions")}
      role -> {String.capitalize(to_string(role)), verbs}
    end
  end

  def preset_boundary_role_from_acl(other) do
    warn(other, "No pattern matched")
    nil
  end

  def create(attrs, opts) do
    # Bonfire.Common.Text.slug
    create(
      e(attrs, :name, nil) || "Untitled role",
      e(attrs, :usage, nil),
      opts
    )
  end

  def create(name, usage, opts) do
    # TODO: whether to show an instance role to all users
    Settings.get([:role_verbs], %{}, opts)
    |> Enum.into(%{})
    |> debug("existing roles")
    |> Map.merge(%{name => %{usage: usage}})
    |> Settings.put([:role_verbs], ..., opts)
  end

  def edit_verb_permission(role_name, verb, value, opts) when value in [true, 1, "true", "1"] do
    current_role = get(role_name, opts)

    remove_cannot(current_role, role_name, verb, opts)

    current_role
    |> Enums.deep_merge(%{can_verbs: [verb]})
    |> Settings.put([:role_verbs, role_name], ..., opts)
  end

  def edit_verb_permission(role_name, verb, value, opts) when value in [false, 0, "false", "0"] do
    current_role = get(role_name, opts)

    remove_can(current_role, role_name, verb, opts)

    current_role
    |> Enums.deep_merge(%{cannot_verbs: [verb]})
    |> Settings.put([:role_verbs, role_name], ..., opts)
  end

  def edit_verb_permission(role_name, verb, value, opts) do
    current_role = get(role_name, opts)

    remove_can(current_role, role_name, verb, opts)

    remove_cannot(current_role, role_name, verb, opts)
  end

  defp remove_can(current_role, role_name, verb, opts) do
    e(current_role, :can_verbs, [])
    |> Enum.reject(&(&1 == verb))
    |> Settings.put([:role_verbs, role_name, :can_verbs], ..., opts)
  end

  def remove_cannot(current_role, role_name, verb, opts) do
    e(current_role, :cannot_verbs, [])
    |> Enum.reject(&(&1 == verb))
    |> Settings.put([:role_verbs, role_name, :cannot_verbs], ..., opts)
  end
end
