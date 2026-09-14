defmodule Bonfire.Boundaries.Scaffold do
  @moduledoc """
  Provides functions to create default boundary fixtures for the instance, for users, and for other actors.

  ⚠️ The row-building itself lives in `Scaffold.Users`, which is a misnomer: nothing in it is specific to users, it turns a config map of circles/ACLs/grants/controlleds into rows for whatever caretaker it is handed. `create_missing_block_boundaries/1` below feeds it a Category. Extracting that into its own module is worth doing the next time something else needs it, rather than now.
  """

  use Bonfire.Common.Config

  alias Bonfire.Boundaries.Scaffold

  defdelegate insert, to: Scaffold.Instance

  defdelegate create_default_boundaries(user, opts \\ []), to: Bonfire.Boundaries.Scaffold.Users
  defdelegate create_missing_boundaries(user, opts \\ []), to: Bonfire.Boundaries.Scaffold.Users

  @doc """
  Creates the boundaries an actor needs for ONE kind of block, if it does not have them yet.

  Users are scaffolded with all of these at signup. A Category (group or topic) is an actor with a character of its own and can be blocked like anyone else, but has never had them, so it gets them the first time somebody blocks it. On demand rather than up front, because most categories are never blocked by anyone and scaffolding all of it for all of them is rows on every group and topic ever created.

  `stereotypes` is what the act in hand actually uses, so a silence creates nothing a ban would need and the other way round. Each entry in `:block_boundaries_by_stereotype` carries its own complete wiring, so they compose without overlapping: `silence_me` is the reverse index kept on whatever is being silenced, while `ghost_them` and `silence_them` are the blocker's OWN lists, which a category needs once it blocks somebody itself, a member ban being exactly that.
  """
  def create_missing_block_boundaries(caretaker, stereotypes) do
    config = Bonfire.Common.Config.get!(:block_boundaries_by_stereotype)

    case stereotypes |> List.wrap() |> Enum.flat_map(&List.wrap(config[&1])) do
      [] ->
        []

      needed ->
        Scaffold.Users.create_missing_boundaries(caretaker, defaults: merge_boundaries(needed))
    end
  end

  # each stereotype's entry is a whole set of circles/acls/grants/controlleds, so composing two of them is a merge per section rather than of the top level
  defp merge_boundaries(sets) do
    %{
      circles: merge_section(sets, :circles),
      acls: merge_section(sets, :acls),
      grants: merge_section(sets, :grants),
      controlleds: merge_controlleds(sets)
    }
  end

  defp merge_section(sets, section),
    do: Enum.reduce(sets, %{}, &Map.merge(&2, Map.get(&1, section, %{})))

  # `controlleds` maps `SELF` to a LIST of ACLs to attach, so two sets have to concatenate under that key rather than one replacing the other
  defp merge_controlleds(sets) do
    Enum.reduce(sets, %{}, fn set, acc ->
      Map.merge(acc, Map.get(set, :controlleds, %{}), fn _self, a, b -> Enum.uniq(a ++ b) end)
    end)
  end
end
