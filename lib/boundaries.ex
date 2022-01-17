defmodule Bonfire.Boundaries do

  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.Identity.Caretaker
  alias Bonfire.Boundaries.Accesses
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Common.Utils

  def repo, do: Bonfire.Common.Config.get!(:repo_module)
  def mailer, do: Bonfire.Common.Config.get!(:mailer_module)

  @doc """
  Assigns the user as the caretaker of the given object or objects,
  replacing the existing caretaker, if any.
  """
  def take_care_of!(things, user) when is_list(things) do
    user_id = Utils.ulid(user)
    repo().insert_all Caretaker, Enum.map(things, &(%{id: Utils.ulid(&1), caretaker_id: user_id})),
      on_conflict: :nothing, conflict_target: [:id]
    Enum.map(things, fn thing ->
      case thing do
        %{caretaker: _} ->
          Map.put(thing, :caretaker, %Caretaker{id: thing.id, caretaker_id: user.id, caretaker: user})
        _ -> thing
      end
    end)
  end
  def take_care_of!(thing, user), do: hd(take_care_of!([thing], user))

end
