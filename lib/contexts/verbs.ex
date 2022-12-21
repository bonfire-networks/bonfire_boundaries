defmodule Bonfire.Boundaries.Verbs do
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  # import Ecto.Query
  alias Bonfire.Data.AccessControl.Verb

  def verbs, do: Bonfire.Common.Config.get!(:verbs)

  def verbs_count, do: Enum.count(verbs)

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

  def get_id(slug), do: verbs()[slug][:id]
  def get_id!(slug), do: get!(slug)[:id]

  def ids(verbs) when is_list(verbs),
    do: Enum.map(verbs, &get_id/1) |> Enum.reject(&is_nil/1)

  def ids(verb) when is_atom(verb), do: ids([verb])

  def role_verbs, do: Config.get(:role_verbs)
  def roles, do: role_verbs |> Keyword.keys()

  def role_names do
    for role <- roles() do
      {role, String.capitalize(to_string(role))}
    end
  end

  def role_from_verb_names(verbs) do
    role_from_verb(verbs, :verb)
  end

  def role_from_verb_ids(verbs) do
    role_from_verb(verbs, :id)
  end

  def role_from_verb(verbs, field \\ :verb, all_role_verbs \\ role_verbs()) do
    cond do
      Enum.count(verbs) == verbs_count() ->
        :caretaker

      true ->
        case all_role_verbs
             |> Enum.filter(fn {_role, a_role_verbs} ->
               verbs ==
                 Enum.map(a_role_verbs, &Map.get(get(&1), field))
                 |> Enum.sort()

               # |> debug
             end) do
          [{role, _verbs}] -> role
          _ -> :custom
        end
    end
  end

  def verbs_for_role(role) do
    role =
      role
      |> Utils.maybe_to_atom()
      |> debug("role")

    if is_atom(role) do
      role_verbs = role_verbs()
      roles = role_verbs |> Keyword.keys()

      cond do
        role in roles -> {:ok, role_verbs[role] || []}
        role in [nil, :none, :custom] -> {:ok, []}
        true -> error(role, l("This role is not defined."))
      end
    else
      error(role, l("This is not a valid role."))
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