defmodule Bonfire.Boundaries.Acls do
  @moduledoc """
  acls represent fully populated access control rules that can be reused
  """
  alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.Identity.Named
  alias Bonfire.Data.Identity.Caretaker

  import Bonfire.Boundaries.Integration
  import Ecto.Query
  alias Ecto.Changeset

  def acls do
    %{
      read_only:  "AC10N1YACCESS1SREADACCESS1", # for stuff noone should be able to interact with
      instance_blocked: "110CA1ADM1NSHAVESA1DEN0VGH"
    }
  end

  def acls_fixture do
    Enum.map(acls(), fn {_k, v} -> %{id: v} end)
  end

  def create(%{}=attrs) when not is_struct(attrs) do
    repo().insert(changeset(attrs))
  end

  def changeset(access \\ %Acl{}, attrs) do
    Acl.changeset(access, attrs)
    |> Changeset.cast_assoc(:named, with: &Named.changeset/2)
    |> Changeset.cast_assoc(:caretaker, with: &Caretaker.changeset/2)
  end

  def list, do: repo().many(
    from(u in Acl,
    left_join: named in assoc(u, :named),
    preload: [:named, :controlled, :caretaker, grants: [:subject_profile, :subject_named, access: [:interacts]]]
  ))


end
