defmodule Bonfire.Boundaries do
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration

  alias Bonfire.Data.Identity.User
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.Identity.Caretaker
  alias Bonfire.Boundaries.{Accesses, Queries}
  alias Pointers
  alias Pointers.Pointer
  import Queries, only: [boundarise: 3]
  import Ecto.Query, only: [from: 2]

  @visibility_verbs [:see, :read]

  def set_boundaries(creator, object, opts) when is_list(opts) and ( is_binary(object) or is_map(object) ) do

    with {:ok, pointer} <- Ecto.Changeset.cast(%Pointers.Pointer{id: ulid(object)}, %{}, [])
                          |> Bonfire.Boundaries.Acls.cast(creator, opts) |> debug("ACL it")
                          |> repo().update()
                          do
      # debug(one_grant: grant)
      {:ok, :granted}
    end
  end


  @doc """
  Assigns the user as the caretaker of the given object or objects,
  replacing the existing caretaker, if any.
  """
  def take_care_of!(things, user) when is_list(things) do
    repo().insert_all(Caretaker, Enum.map(things, &(%{id: Utils.ulid(&1), caretaker_id: Utils.ulid(user)})), on_conflict: :nothing, conflict_target: [:id]) #|> debug
    Enum.map(things, fn thing ->
      case thing do
        %{caretaker: _} ->
          Map.put(thing, :caretaker, %Caretaker{id: thing.id, caretaker_id: Utils.ulid(user), caretaker: user})
        _ -> thing
      end
    end)
  end
  def take_care_of!(thing, user), do: hd(take_care_of!([thing], user))

  def user_default_boundaries() do
    Config.get!(:user_default_boundaries)
  end

  def preset(preset) when is_binary(preset), do: preset
  def preset(opts), do: maybe_from_opts(opts, :boundary)

  @doc """
  Loads binaries according to boundaries (which are assumed to be ULID pointer IDs).
  Anything else is returned as-is, except lists which are iterated and merged back into the resulting list.
  """
  def load_pointers(item, opts) when not is_list(item) do
    if is_binary(item), do: repo().one(load_query(item, opts)), else: item
  end
  def load_pointers(items, opts) do
    debug(items, "items")
    items = List.wrap(items)
    case Enum.filter(items, &is_ulid?/1) do
      [] -> items
      ids ->
        # load and index
        loaded = Pointers.Util.index_objects_by_id(repo().many(load_query(ids, opts)))
        debug(loaded, "loaded")
        items
        |> Enum.map(&if(is_ulid?(&1), do: loaded[&1], else: &1))
    end
  end

  defp load_query(ids, opts) do
    from(p in Pointers.query_base(), where: p.id in ^List.wrap(ids))
    |> boundarise(id, opts)
  end
end
