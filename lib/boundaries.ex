defmodule Bonfire.Boundaries do
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration

  # alias Bonfire.Data.Identity.User
  # alias Bonfire.Boundaries.Circles
  # alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.Identity.Caretaker
  alias Bonfire.Boundaries.{Acls, Queries}
  alias Pointers
  # alias Pointers.Pointer
  import Queries, only: [boundarise: 3]
  import Ecto.Query, only: [from: 2]

  # @visibility_verbs [:see, :read]
  @public_acls [:guests_may_see, :guests_may_read, :guests_may_see_read]
  @local_acls [:locals_may_interact, :locals_may_reply]

  def preset_boundary_name_from_acl(acl) do
    public_acl_ids = @public_acls
    |> Enum.map(&Acls.get_id!/1)

    local_acl_ids = @local_acls
    |> Enum.map(&Acls.get_id!/1)

    acl = ulid(acl)

    cond do
      acl in public_acl_ids -> "public"
      acl in local_acl_ids -> "local"
      true -> "mentions"
    end
  end

  def set_boundaries(creator, object, opts) when is_list(opts) and ( is_binary(object) or is_map(object) ) do

    with {:ok, _pointer} <- Ecto.Changeset.cast(%Pointers.Pointer{id: ulid(object)}, %{}, [])
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
  Lists which are iterated and return a [sub]list with only permitted pointers.
  """
  def load_pointers(items, opts) when is_list(items)  do
    # debug(items, "items")
    case ulid(items) do
      [] -> []
      nil -> []
      ids ->
        repo().many(load_query(ids, opts))
    end
  end
  def load_pointers(item, opts) do
    case ulid(item) do
      id when is_binary(id) ->

        repo().one(load_query(id, opts))

      _ ->
        error(item, "Expected an object or ULID ID, could not check boundaries for")
        nil
    end
  end

  defp load_query(ids, opts) do
    from(p in Pointers.query_base(), where: p.id in ^List.wrap(ids))
    |> boundarise(id, opts)
  end
end
