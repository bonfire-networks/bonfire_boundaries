defmodule Bonfire.Boundaries.Verbs do

  alias Bonfire.Data.AccessControl.Verb
  import Bonfire.Boundaries.Integration
  import Ecto.Query

  def verbs, do: Bonfire.Common.Config.get!(:verbs)

  def get(slug) when is_atom(slug), do: verbs()[slug]
  def get(id_or_name) when is_binary(id_or_name), do: get_tuple(id_or_name) |> elem(1)

  def get_tuple(id_or_name) when is_binary(id_or_name) do
    Enum.find verbs, fn {_slug, verb} ->
      verb[:id] == id_or_name or verb[:verb] == id_or_name
    end
  end

  def get_slug(id), do: get_tuple(id) |> elem(0)

  def get!(id_or_name) when is_atom(id_or_name) or is_binary(id_or_name) do
    get(id_or_name) || raise RuntimeError, message: "Missing default verb: #{inspect(id_or_name)}"
  end

  def get_id(slug), do: Map.get(verbs(), slug, %{})[:id]

  def get_id!(slug), do: get!(slug)[:id]

  def ids(verbs) when is_list(verbs), do: Enum.map(verbs, &get_id/1) |> Enum.reject(&is_nil/1)
  def ids(verb) when is_atom(verb), do: ids([verb])

  def create(%{}=attrs) when not is_struct(attrs) do
    repo().insert(changeset(attrs))
  end

  def changeset(verb \\ %Verb{}, attrs) do
    Verb.changeset(verb, attrs)
  end

  def list(from \\ :db)
  def list(:db) do
    repo().many(Verb)
    |> Enum.reduce(%{}, fn t, acc ->
      Map.merge(acc, %{t.verb => t})
    end)
  end
  def list(:code), do: verbs()

  def list_verbs_debug() do
    Enum.concat(list_verbs_db_vs_code(), list_verbs_code_vs_db())
    |> Enum.sort(:desc)
    |> Enum.dedup
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
      else e ->
        {:error, "Verb present in DB but not in code", verb}
      end
    end)
    |> Enum.sort(:desc)
  end


  defp list_verbs_code_vs_db() do
    db_verbs = list(:db)

    list(:code)
    |> Enum.map(fn {schema, p} when is_atom(schema) ->

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

      _ -> nil
    end)
    |> Enum.sort(:desc)
    |> Enum.dedup
  end


end
