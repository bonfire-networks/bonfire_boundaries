defmodule Bonfire.Boundaries.Roles do
  use Bonfire.Common.Utils
  import Untangle
  # import Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.Verbs
  alias Bonfire.Data.AccessControl.Acl

  @config_key :role_verbs

  def role_verbs(usage \\ :all, opts \\ [])
  def role_verbs(:ops, opts), do: role_verbs(:all, opts)
  def role_verbs(:all, opts), do: do_get(@config_key, opts)

  def role_verbs(_, opts),
    do:
      do_get(@config_key, opts)
      |> Enums.fun(:filter, fn
        %{usage: :ops} -> false
        _ -> true
      end)

  def get(role_name, opts \\ []) do
    do_get([@config_key, role_name], opts)
    |> Enum.into(%{})
  end

  defp do_get(key, opts) do
    opts =
      to_options(opts)
      |> Keyword.put_new(:one_scope_only, true)

    if opts[:scope] == :instance do
      Config.get(key, %{})
    else
      Settings.get(key, %{}, opts)
    end

    # |> debug("gottt")
  end

  # def cannot_role_verbs(usage \\ nil)
  # def cannot_role_verbs(:ops), do: Config.get(:cannot_role_verbs)
  # def cannot_role_verbs(_),
  #   do:
  #     Config.get(:cannot_role_verbs)
  #     |> Enums.fun(:filter, fn
  #       %{usage: :ops} -> false
  #       _ -> true
  #     end)

  def roles_for_dropdown(usage \\ nil, opts) do
    opts =
      to_options(opts)
      |> Keyword.put_new(:one_scope_only, false)

    roles = role_verbs(usage, opts) |> Enums.fun(:keys)

    # negative =
    #   cannot_role_verbs(usage)
    #   |> Enums.fun(:keys)
    #   |> debug()

    debug(
      for role <- roles || [] do
        {role, Recase.to_title(to_string(role))}
      end
    )

    # ++
    #   debug(
    #     for role <- negative || [] do
    #       {"cannot_#{role}", l("Cannot") <> " " <> Recase.to_title(to_string(role))}
    #     end
    #   )
  end

  defp role_from_verb_names(verbs) do
    role_from_verb(verbs, :verb) || :custom
  end

  def role_from_grants(grants, opts) do
    opts =
      to_options(opts)
      |> Keyword.put_new(:one_scope_only, false)

    all_role_verbs = role_verbs(:all, opts)

    {positive, negative} =
      Enum.split_with(grants, fn
        %{value: value} -> value
      end)
      |> debug("yes vs no")

    cond do
      positive != [] and negative == [] ->
        verb_ids_from_grants(positive)
        |> debug("this is a role with only positive permissions")
        |> role_from_verb(:id, all_role_verbs) ||
          if(opts[:fallback_to_list], do: Enum.join(display_verb_grants(positive, l("Can")), ";"))

      positive == [] and negative != [] ->
        verb_ids_from_grants(negative)
        |> debug("this is a role with only negative permissions")
        |> cannot_role_from_verb(:id, all_role_verbs) ||
          if(opts[:fallback_to_list],
            do: Enum.join(display_verb_grants(negative, l("Cannot")), ";")
          )

      true ->
        debug("this is a role with both positive and negative permissions")

        if(opts[:fallback_to_list],
          do:
            Enum.join(
              display_verb_grants(positive, l("Can")) ++
                display_verb_grants(negative, l("Cannot")),
              " ; "
            )
        )
    end
    |> debug("computed role") ||
      :custom
  end

  defp display_verb_grants(grants, prefix) do
    Enum.map(grants, &"#{prefix} #{e(&1, :verb, :verb, nil)}")
  end

  defp verb_ids_from_grants(grants) do
    Enum.map(grants, &e(&1, :verb_id, nil))
  end

  def cannot_role_from_verb(
        verbs,
        verb_field \\ :verb,
        all_role_verbs \\ role_verbs(:all),
        role_for_all \\ :read,
        verbs_field \\ :cannot_verbs
      ) do
    role_from_verb(verbs, verb_field, all_role_verbs, role_for_all, verbs_field)
  end

  def role_from_verb(
        verbs,
        verb_field \\ :verb,
        all_role_verbs \\ role_verbs(:all),
        role_for_all \\ :administer,
        verbs_field \\ :can_verbs
      ) do
    if Enum.count(verbs) == Verbs.verbs_count() do
      role_for_all
    else
      case all_role_verbs
           |> debug("all_role_verbs")
           |> Enum.filter(fn
             {role, %{^verbs_field => a_role_verbs}} ->
               verbs ==
                 a_role_verbs
                 |> Enum.map(&e(Verbs.get(&1), verb_field, []))
                 |> Enum.sort()
                 |> debug("#{role} role_verbs")

             _other ->
               # debug(other, "other")
               false
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

  def verbs_for_role(role, opts \\ [])

  def verbs_for_role([role], opts) do
    verbs_for_role(role, opts)
  end

  def verbs_for_role(role, opts) do
    opts =
      to_options(opts)
      |> Keyword.put_new(:one_scope_only, false)

    do_verbs_for_role(to_string(role), Types.maybe_to_atom(role), role_verbs(:all, opts), opts)
  end

  defp do_verbs_for_role(role_string, role, all_role_verbs, _opts) do
    roles = all_role_verbs |> Enums.fun(:keys)

    cond do
      role in roles ->
        {:ok, e(all_role_verbs, role, :can_verbs, []), e(all_role_verbs, role, :cannot_verbs, [])}

      role_string in roles ->
        {:ok, e(all_role_verbs, role, :can_verbs, []), e(all_role_verbs, role, :cannot_verbs, [])}

      role in [nil, :none, :custom] ->
        {:ok, [], []}

      true ->
        debug(roles, "available roles")
        e = "This role is not properly defined."
        # raise e
        error(role, e)
    end
  end

  def preset_boundary_role_from_acl(%{verbs: verbs} = _summary) do
    preset_boundary_role_from_acl(verbs)
  end

  def preset_boundary_role_from_acl(verbs) when is_list(verbs) do
    # debug(summary)
    case role_from_verb_names(verbs) do
      :administer -> {l("Administer"), l("Full permissions")}
      role -> {Recase.to_title(to_string(role)), verbs}
    end
  end

  def preset_boundary_role_from_acl(other) do
    if Types.is_ulid?(other) do
      preset_boundary_role_from_acl(%Acl{id: other})
    else
      warn(other, "No role pattern matched")
      nil
    end
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
    # debug(opts, "opts")
    # TODO: whether to show an instance role to all users
    role_verbs(:all, opts)
    |> Enum.into(%{})
    |> Map.merge(%{name => %{usage: usage}})
    |> debug("merged with existing roles")
    |> Settings.put([@config_key], ..., opts)
  end

  def edit_verb_permission(role_name, verb, value, opts)
      when value in [true, 1, "true", "1"] and is_atom(verb) do
    # positive permission
    get(role_name, opts)
    |> remove_cannot(verb, opts)
    |> Enums.deep_merge(%{can_verbs: [verb]})
    |> do_put(role_name, ..., opts)
  end

  def edit_verb_permission(role_name, verb, value, opts)
      when value in [false, 0, "false", "0"] and is_atom(verb) do
    # negative permission
    get(role_name, opts)
    |> remove_can(verb, opts)
    |> Enums.deep_merge(%{cannot_verbs: [verb]})
    |> do_put(role_name, ..., opts)
  end

  def edit_verb_permission(role_name, verb, _value, opts) when is_atom(verb) do
    # reset to default (nil)
    get(role_name, opts)
    |> remove_can(verb, opts)
    |> remove_cannot(verb, opts)
    |> do_put(role_name, ..., opts)
  end

  defp do_put(role_name, values, opts) do
    debug(values, "updated role")
    Settings.put([@config_key, role_name], values, opts)
  end

  defp remove_can(current_role, verb, opts) do
    do_remove_verb(:can_verbs, current_role, verb, opts)
  end

  defp remove_cannot(current_role, verb, opts) do
    do_remove_verb(:cannot_verbs, current_role, verb, opts)
  end

  defp do_remove_verb(key, current_role, verb, _opts) do
    debug(verb, "remove verb")

    Map.put(
      current_role,
      key,
      Enum.reject(e(current_role, key, []), &(&1 == verb)) |> debug() |> Enums.filter_empty([])
    )
  end

  def reset_instance_roles do
    Settings.put([@config_key], nil, scope: :instance, skip_boundary_check: true)
    Config.delete(@config_key, :bonfire)
  end

  def split_tuples_can_cannot(tuples) do
    tuples
    |> Enum.split_with(fn {_circle, role} ->
      not String.starts_with?(to_string(role), "cannot_")
    end)
  end
end
