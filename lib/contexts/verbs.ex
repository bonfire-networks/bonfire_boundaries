defmodule Bonfire.Boundaries.Verbs do
  @moduledoc """
  Verbs represent actions users can perform, such as reading a post or replying to a message. Each verb has a unique ID and are defined in configuration.
  """
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  # import Ecto.Query
  alias Bonfire.Data.AccessControl.Verb

  @doc """
  Returns the list of verbs from the configuration.
  """
  def verbs, do: Bonfire.Common.Config.get!(:verbs)

  @doc """
  Returns the count of verbs in the configuration.
  """
  def verbs_count, do: Enum.count(verbs())

  @doc """
  Returns the list of verb slugs.

  ## Examples

      iex> Bonfire.Boundaries.Verbs.slugs()
      [:read, :write]
  """
  def slugs, do: Keyword.keys(verbs())

  @doc """
  Retrieves a verb by its slug or ID.

  ## Examples

      iex> Bonfire.Boundaries.Verbs.get(:read)
      %{id: "read_id", verb: :read}

      iex> Bonfire.Boundaries.Verbs.get("read_id")
      %{id: "read_id", verb: :read}

      iex> Bonfire.Boundaries.Verbs.get("non_existent")
      nil
  """
  def get(slug, all_verbs \\ verbs())
  def get(slug, all_verbs) when is_atom(slug), do: all_verbs[slug]

  def get(id_or_name, all_verbs) when is_binary(id_or_name) do
    case get_tuple(id_or_name, all_verbs) do
      {_slug, verb} -> verb
      _ -> nil
    end
  end

  def get({_, %Verb{} = verb}, _all_verbs), do: verb
  def get({_, %{id: _, verb: _} = verb}, _all_verbs), do: verb

  @doc """
  Retrieves a verb tuple by its ID or name.

  ## Examples

      iex> Bonfire.Boundaries.Verbs.get_tuple("read_id")
      {:read, %{id: "read_id", verb: :read}}

      iex> Bonfire.Boundaries.Verbs.get_tuple("non_existent")
      nil
  """
  def get_tuple(id_or_name, all_verbs \\ verbs()) when is_binary(id_or_name) do
    Enum.find(all_verbs, fn {_slug, verb} ->
      verb[:id] == id_or_name or verb[:verb] == id_or_name
    end)
  end

  @doc """
  Retrieves a verb slug by its ID or name.

    ## Examples

      iex> Bonfire.Boundaries.Verbs.get_slug("read_id")
      :read
  """
  def get_slug(id_or_name, all_verbs \\ verbs()) do
    case get_tuple(id_or_name, all_verbs) do
      {slug, _verb} -> slug
      _ -> nil
    end
  end

  @doc """
  Retrieves verb details by its ID or name, raising an error if not found.

  ## Examples

      iex> Bonfire.Boundaries.Verbs.get!("read")
      %{id: "some_id", verb: :read}  # Example output

      iex> Bonfire.Boundaries.Verbs.get!("non_existent_id")
      ** (RuntimeError) Missing default verb: "non_existent_id"
  """
  def get!(id_or_name, all_verbs \\ verbs()) when is_atom(id_or_name) or is_binary(id_or_name) do
    get(id_or_name, all_verbs) ||
      raise RuntimeError,
        message: "Missing default verb: #{inspect(id_or_name)}"
  end

  @doc """
  Retrieves a verb ID by its slug.

  ## Examples

      iex> Bonfire.Boundaries.Verbs.get_id(:read)
      "read_id"

      iex> Bonfire.Boundaries.Verbs.get_id("read")
      "read_id"

      iex> Bonfire.Boundaries.Verbs.get_id("non_existent")
      nil
  """
  def get_id(slug, all_verbs \\ verbs())
  def get_id(slug, all_verbs) when is_atom(slug), do: all_verbs[slug][:id]

  def get_id(id_or_slug, all_verbs) when is_binary(id_or_slug) do
    case maybe_to_atom(id_or_slug) do
      slug when not is_nil(slug) and is_atom(slug) -> get_id(slug, all_verbs)
      _ -> ulid(id_or_slug)
    end
  end

  @doc """
  Retrieves a verb ID by its slug or ID, raising an error if not found.

      iex> Bonfire.Boundaries.Verbs.get_id!(:read)
      "read_id"

      iex> Bonfire.Boundaries.Verbs.get_id!("non_existent")
      ** (RuntimeError) Missing default verb: "non_existent"
  """
  def get_id!(slug, all_verbs \\ verbs()), do: get!(slug, all_verbs)[:id]

  @doc """
  Retrieves the IDs of the given verbs.

      iex> Bonfire.Boundaries.Verbs.ids([:read, :write])
      ["read_id", "write_id"]

      iex> Bonfire.Boundaries.Verbs.ids(:read)
      ["read_id"]
  """
  def ids(verbs, all_verbs \\ verbs())

  def ids(verbs, all_verbs) when is_list(verbs),
    do: Enum.map(verbs, &get_id(&1, all_verbs)) |> Enum.reject(&is_nil/1)

  def ids(verb, all_verbs) when is_atom(verb), do: ids([verb], all_verbs)

  @doc """
  Creates a new verb with the given attributes.

  ## Examples

  > Bonfire.Boundaries.Verbs.create(%{verb: :new_verb, description: "A new verb"})
  {:ok, %Verb{id: "new_verb_id", verb: :new_verb, description: "A new verb"}}
  """
  def create(%{} = attrs) when not is_struct(attrs) do
    repo().insert(changeset(attrs))
  end

  @doc """
  Returns a changeset for the given verb and attributes.

  ## Examples

      iex> Bonfire.Boundaries.Verbs.changeset(%{verb: :new_verb, description: "A new verb"})
  """
  def changeset(verb \\ %Verb{}, attrs) do
    Verb.changeset(verb, attrs)
  end

  @doc """
  Lists the verbs from the specified source and key.

  ## Examples

      iex> Bonfire.Boundaries.Verbs.list(:db, :verb)
      %{read: %Verb{id: "read_id", verb: :read}, write: %Verb{id: "write_id", verb: :write}}

      iex> Bonfire.Boundaries.Verbs.list(:instance, :id)
      ["read_id", "write_id"]
  """
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

  @doc """
  Returns a debug list of verbs by comparing the database and code.

  ## Examples

      > Bonfire.Boundaries.Verbs.list_verbs_debug()
      # Example output:
      [ok: :read, error: "Code and DB have differing IDs for the same verb", ...]  
  """
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
