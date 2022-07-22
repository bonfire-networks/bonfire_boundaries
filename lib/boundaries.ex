defmodule Bonfire.Boundaries do
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration

  # alias Bonfire.Data.Identity.User
  # alias Bonfire.Boundaries.Circles
  # alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.Identity.Caretaker
  alias Bonfire.Boundaries.{Acls, Controlleds, Queries}
  alias Pointers
  # alias Pointers.Pointer
  import Queries, only: [boundarise: 3]
  import Ecto.Query

  def preset_name(boundaries) when is_list(boundaries) do
    debug(boundaries, "inputted")
    cond do # Note: only one applies, in priority from most to least restrictive
      "mentions" in boundaries -> "mentions"
      "local" in boundaries -> "local"
      "federated" in boundaries -> "federated"
      "public" in boundaries -> "public"
      true ->
        # debug(boundaries, "No preset boundary set")
        nil
    end
    |> debug("computed")
  end
  def preset_name(other) do
    boundaries_set(other)
    |> preset_name()
  end

  def boundaries_set(text) when is_binary(text) do
    text
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end
  def boundaries_set(list) when is_list(list) do
    list
  end
  def boundaries_set(other) do
    warn(other, "Invalid boundaries set")
    []
  end

  def list_object_acls(object) do
    Controlleds.list_on_object(object)
    |> Enum.map(&(&1.acl))
  end

  def acls_from_preset_boundary_names(presets) when is_list(presets), do: Enum.flat_map(presets, &acls_from_preset_boundary_names/1)
  def acls_from_preset_boundary_names(preset) do
    case preset do
      preset when is_binary(preset) ->
        acls = Config.get!(:preset_acls)[preset]
        if acls do
          acls
        else
          []
        end
      _ -> []
    end
  end

  def preset_boundary_tuple_from_acl(acl) do
    preset_acls = Config.get!(:preset_acls_all)

    public_acl_ids = preset_acls["public"]
    |> Enum.map(&Acls.get_id!/1)

    local_acl_ids = preset_acls["local"]
    |> Enum.map(&Acls.get_id!/1)

    acl = ulid(acl)

    cond do
      acl in public_acl_ids -> {"public", l "Public"}
      acl in local_acl_ids -> {"local", l "Local Instance"}
      true -> {"mentions", l "Mentions"}
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
        load_query(ids, e(opts, :ids_only, nil), opts)
        |> repo().many()
    end
  end
  def load_pointers(item, opts) do
    case ulid(item) do
      id when is_binary(id) ->

        load_query(id, e(opts, :ids_only, nil), opts)
        |> repo().one()

      _ ->
        error(item, "Expected an object or ULID ID, could not check boundaries for")
        nil
    end
  end

  defp load_query(ids, true, opts) do
    load_query(ids, nil, opts)
    |> select([main], [:id])
  end
  defp load_query(ids, _, opts) do
    from(p in Pointers.query_base(), where: p.id in ^List.wrap(ids))
    |> boundarise(id, opts)
  end
end
