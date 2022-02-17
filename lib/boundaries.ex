defmodule Bonfire.Boundaries do
  use Bonfire.Common.Utils

  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.Identity.Caretaker
  alias Bonfire.Boundaries.Accesses
  alias Bonfire.Boundaries.Circles

  def repo, do: Bonfire.Common.Config.get!(:repo_module)
  def mailer, do: Bonfire.Common.Config.get!(:mailer_module)

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

end
