defmodule Bonfire.Boundaries.Verbs do

  alias Bonfire.Data.AccessControl.Verb
  import Bonfire.Boundaries.Integration
  import Ecto.Query

  def verbs do
    Bonfire.Common.Config.get!(:verbs)
  end

def get(verb) do
Bonfire.Common.Config.get!([:verbs, verb])
end

  def verbs_fixture do
    Enum.map(verbs(), fn {k, v} -> %{id: v, verb: to_string(k)} end)
  end

  def create(%{}=attrs) when not is_struct(attrs) do
    repo().insert(changeset(attrs))
  end

  def changeset(verb \\ %Verb{}, attrs) do
    Verb.changeset(verb, attrs)
  end

  def list, do: repo().all(from(u in Verb))

end
