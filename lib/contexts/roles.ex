defmodule Bonfire.Boundaries.Roles do
  @moduledoc """
   Roles are groups of verbs associated with permissions. While not stored in the database, they are defined at the configuration level to enhance readability and user experience.

  Here are some preset roles and their associated actions:

  - **Read**: can discover the content in lists (like feeds) and read it; request permission for another verb (e.g., request to follow).
  - **Interact**: can read, plus like an object (and notify the author); follow a user or thread; boost an object (and notify the author); pin something to highlight it.
  - **Participate**: can interact, plus reply to an activity or post; mention a user or object (and notify them); send a message.
  - **Contribute**: can participate, plus create a post or other object; tag a user or object or publish in a topic.
  - **Caretaker**: can perform all of the above actions and more, including actions like deletion.

  There are also negative roles, indicating actions which you specifically do not want to allow a particular circle or user to do, such as:

  - **Cannot Read**: not discoverable in lists or readable, and also can't interact or participate.
  - **Cannot Interact**: cannot perform any actions related to interaction, including liking, following, boosting, and pinning, and also can't participate.
  - **Cannot Participate**: cannot perform any actions related to participation, including replying, mentioning, and sending messages.

  Negative permissions always take precedence over positive or undefined permissions. For example, For example, if you share something giving permission to anyone to read and reply to it, and you assign the *Cannot Participate* role to your *Likely to troll* circle, the people in that circle will be able to read the content but will not be able to reply to it.

  > Note that these negative roles do not grant any additional permissions. Assigning the Cannot Participate role to someone who wouldn't otherwise be able to read the content does not mean they will now have the ability to do so. Negative roles simply limit or override any permissions defined elsewhere, ensuring that the specified actions are explicitly restricted.
  """

  use Bonfire.Common.Utils
  import Untangle
  # import Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.Verbs
  alias Bonfire.Data.AccessControl.Acl

  @config_key :role_verbs

  @doc """
  Retrieves role verbs based on the given `usage`.

  ## Examples

      iex> role_verbs(:all, scope: :instance)
      # returns all instance-level role verbs

      iex> role_verbs(nil, current_user: me)
      # returns my role verbs 
  """
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

  @doc """
  Retrieves the details of a role by `role_name`.

  ## Examples

      iex> get(:admin)
      # returns admin role details
  """
  def get(role_name, opts \\ []) do
    do_get([@config_key, role_name], opts)
    |> Enum.into(%{})
  end

  defp do_get(key, opts) do
    opts =
      to_options(opts)
      |> Keyword.put_new(:one_scope_only, true)

    if opts[:scope] in [:instance, :instance_wide] do
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

  @doc """
  Returns a list of roles to be used in a user's a dropdown menu.

  ## Examples

      iex> roles_for_dropdown(:ops, current_user: me)
  """
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

  @doc """
  Determines the matching role (if any) from a list of verbs.

  ## Examples

      iex> role_from_grants(grants)
  """
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

  @doc """
  Determines a matching negative role (if any) from a list of verbs.

  ## Examples

      iex> cannot_role_from_verb(verbs)
  """
  def cannot_role_from_verb(
        verbs,
        verb_field \\ :verb,
        all_role_verbs \\ role_verbs(:all),
        role_for_all \\ :read,
        verbs_field \\ :cannot_verbs
      ) do
    role_from_verb(verbs, verb_field, all_role_verbs, role_for_all, verbs_field)
  end

  @doc """
  Determines a matching positive role (if any) from a list of verbs.

  ## Examples

      iex> role_from_verb(verbs)
  """
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

  @doc """
  Returns a list of positive and negative verbs for the given role.

  ## Examples

      iex> verbs_for_role(:admin)
      {:ok, positive_verbs, negative_verbs}
  """
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

  @doc """
  Determines the preset boundary role from an ACL summary or list of verbs.

  ## Examples

      iex> preset_boundary_role_from_acl(%{verbs: verbs})

      iex> preset_boundary_role_from_acl(verbs)
  """
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

  @doc """
  Creates a role with given attributes and options.

  ## Examples

      iex> create(attrs, opts)
  """
  def create(attrs, opts) do
    # Bonfire.Common.Text.slug
    create(
      e(attrs, :name, nil) || "Untitled role",
      e(attrs, :usage, nil),
      opts
    )
  end

  @doc """
  Creates a role with a given name, usage, and options.

  ## Examples

      iex> create("Admin", :admin, opts)
      # creates an admin role with the provided options
  """
  def create(name, usage, opts) do
    # debug(opts, "opts")
    # TODO: whether to show an instance role to all users
    role_verbs(:all, opts)
    |> Enum.into(%{})
    |> Map.merge(%{name => %{usage: usage}})
    |> debug("merged with existing roles")
    |> Settings.put([@config_key], ..., opts)
  end

  @doc """
  Edits a verb permission for a role 

  ## Examples

      iex> edit_verb_permission(:admin, :read, true, opts)
      # updates the read permission for the admin role to true

      iex> edit_verb_permission(:admin, :read, false, opts)
      # updates the read permission for the admin role to false

      iex> edit_verb_permission(:admin, :read, nil, opts)
      # resets the read permission for the admin role to default
  """
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

  @doc """
  Clears instance-wide roles from config.
  """
  def reset_instance_roles do
    Settings.put([@config_key], nil, scope: :instance, skip_boundary_check: true)
    Config.delete(@config_key, :bonfire)
  end

  @doc """
  Splits a list of tuples into can and cannot categories.

  ## Examples

      iex> split_tuples_can_cannot(tuples)
      # splits tuples into can and cannot categories
  """
  def split_tuples_can_cannot(tuples) do
    tuples
    |> Enum.split_with(fn {_circle, role} ->
      not String.starts_with?(to_string(role), "cannot_")
    end)
  end
end
