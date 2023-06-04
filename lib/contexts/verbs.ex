defmodule Bonfire.Boundaries.Verbs do
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  # import Ecto.Query
  alias Bonfire.Data.AccessControl.Verb

  def verbs, do: Bonfire.Common.Config.get!(:verbs)

  def verbs_count, do: Enum.count(verbs())

  def slugs, do: Keyword.keys(verbs())

  def get(slug) when is_atom(slug), do: verbs()[slug]

  def get(id_or_name) when is_binary(id_or_name),
    do: get_tuple(id_or_name) |> elem(1)

  def get_tuple(id_or_name) when is_binary(id_or_name) do
    Enum.find(verbs(), fn {_slug, verb} ->
      verb[:id] == id_or_name or verb[:verb] == id_or_name
    end)
  end

  def get_slug(id), do: get_tuple(id) |> elem(0)

  def get!(id_or_name) when is_atom(id_or_name) or is_binary(id_or_name) do
    get(id_or_name) ||
      raise RuntimeError,
        message: "Missing default verb: #{inspect(id_or_name)}"
  end

  def get_id(slug) when is_atom(slug), do: verbs()[slug][:id]

  def get_id(id_or_slug) when is_binary(id_or_slug) do
    case maybe_to_atom(id_or_slug) do
      slug when not is_nil(slug) and is_atom(slug) -> get_id(slug)
      _ -> ulid(id_or_slug)
    end
  end

  def get_id!(slug), do: get!(slug)[:id]

  def ids(verbs) when is_list(verbs),
    do: Enum.map(verbs, &get_id/1) |> Enum.reject(&is_nil/1)

  def ids(verb) when is_atom(verb), do: ids([verb])

  def role_verbs, do: Config.get(:role_verbs)
  def negative_role_verbs, do: Config.get(:negative_role_verbs)

  def roles_for_dropdown do
    positive = role_verbs() |> Keyword.keys()
    negative = negative_role_verbs() |> Keyword.keys()

    for role <- positive do
      {role, String.capitalize(to_string(role))}
    end ++
      for role <- negative do
        {"negative_#{role}", l("Cannot") <> " " <> String.capitalize(to_string(role))}
      end
  end

  def role_from_verb_names(verbs) do
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
        all_role_verbs \\ negative_role_verbs(),
        role_for_all \\ :read
      ) do
    "negative_#{role_from_verb(verbs, field, all_role_verbs, role_for_all) || :none}"
  end

  def role_from_verb(
        verbs,
        field \\ :verb,
        all_role_verbs \\ role_verbs(),
        role_for_all \\ :administer
      ) do
    cond do
      Enum.count(verbs) == verbs_count() ->
        role_for_all

      true ->
        case all_role_verbs
             |> debug("all_role_verbs")
             |> Enum.filter(fn {_role, a_role_verbs} ->
               verbs ==
                 Enum.map(a_role_verbs, &Map.get(get(&1), field))
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

  def verbs_for_role("negative_" <> role) do
    do_verbs_for_role(role, false, negative_role_verbs())
  end

  def verbs_for_role(role) do
    do_verbs_for_role(role, true, role_verbs())
  end

  defp do_verbs_for_role(role, value, role_verbs) do
    role =
      role
      |> Types.maybe_to_atom()
      |> debug("role")

    if is_atom(role) do
      roles = role_verbs |> Keyword.keys()

      cond do
        role in roles ->
          {:ok, value, role_verbs[role] || []}

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

  def create(%{} = attrs) when not is_struct(attrs) do
    repo().insert(changeset(attrs))
  end

  def changeset(verb \\ %Verb{}, attrs) do
    Verb.changeset(verb, attrs)
  end

  def list(from \\ :db, key \\ :verb)

  def list(:db, key) do
    repo().many(Verb)
    |> Enum.reduce(%{}, fn t, acc ->
      Map.merge(acc, %{Map.get(t, key) => t})
    end)
  end

  def list(:instance, :id), do: list(:instance, nil) |> Enum.map(&(elem(&1, 1) |> ulid()))

  def list(:instance, _),
    do: verbs() |> Enum.filter(&(elem(&1, 1) |> e(:scope, nil) == :instance))

  def list(_, _), do: verbs()

  def list_verbs_debug() do
    Enum.concat(list_verbs_db_vs_code(), list_verbs_code_vs_db())
    |> Enum.sort(:desc)
    |> Enum.dedup()
  end

  defp list_verbs_db_vs_code() do
    list(:db)
    |> Enum.map(fn {verb, t} ->
      verb = verb |> String.downcase() |> String.to_atom()

      with %{} = p <- get(verb) do
        if t.id == p.id do
          {:ok, verb}
        else
          {:error, "Code and DB have differing IDs for the same verb", verb, p.id, t.id}
        end
      else
        _e ->
          {:error, "Verb present in DB but not in code", verb}
      end
    end)
    |> Enum.sort(:desc)
  end

  defp list_verbs_code_vs_db() do
    db_verbs = list(:db)

    list(:code)
    |> Enum.map(fn
      {schema, p} when is_atom(schema) ->
        t = Map.get(db_verbs, p.verb)

        if not is_nil(t) do
          if t.id == p.id do
            {:ok, p.verb}
          else
            {:error, "Code and DB have differing IDs for the same verb", p.verb, p.id, t.id}
          end
        else
          {:error, "Verb present in code but not in DB", p.verb}
        end

      _ ->
        nil
    end)
    |> Enum.sort(:desc)
    |> Enum.dedup()
  end
end
