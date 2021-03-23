defmodule Bonfire.Boundaries.Accesses do

  alias Bonfire.Data.AccessControl.Access
  alias Bonfire.Data.Social.Named
  alias Bonfire.Data.Identity.Caretaker

  import Bonfire.Boundaries.Integration
  import Ecto.Query
  alias Ecto.Changeset

  def accesses do
    %{ read_only:  "2HE0N1YACCESS1SREADACCESS1",
       administer: "2T0TA1C0NTR010VERS0METH1NG",
       no_no_no: "1D0N0TG1VEC0NSENTT0ANYVERB",
    }
  end

  def accesses_fixture do
    Enum.map(accesses(), fn {_k, v} -> %{id: v, can_see: true, can_read: true} end)
  end

  def create(%{}=attrs) when not is_struct(attrs) do
    repo().insert(changeset(attrs))
  end

  def changeset(access \\ %Access{}, attrs) do
    Access.changeset(access, attrs)
    |> Changeset.cast_assoc(:named, with: &Named.changeset/2)
    |> Changeset.cast_assoc(:caretaker, with: &Caretaker.changeset/2)
  end

  def list, do: repo().all(from(u in Access, left_join: named in assoc(u, :named), preload: [:named]))

end
