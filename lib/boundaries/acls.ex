defmodule Bonfire.Boundaries.Acls do
  @moduledoc """
  acls represent fully populated access control rules that can be reused
  """
  alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.Identity.Named
  alias Bonfire.Data.Identity.Caretaker

  import Bonfire.Boundaries
  import Ecto.Query
  alias Ecto.Changeset
  import EctoSparkles

  # special built-in acls (eg, guest, local, activity_pub)
  def acls, do: Bonfire.Common.Config.get([:acls])

  def get(slug) when is_atom(slug), do: acls()[slug]
  def get!(slug) when is_atom(slug) do
    get(slug) || raise RuntimeError, message: "Missing default acl: #{inspect(slug)}"
  end

  def get_id(slug), do: Map.get(acls(), slug, %{})[:id]

  def get_id!(slug), do: get!(slug)[:id]

  def create(%{}=attrs) when not is_struct(attrs) do
    repo().insert(changeset(attrs))
  end

  def changeset(acl \\ %Acl{}, attrs) do
    Acl.changeset(acl, attrs)
    # |> IO.inspect(label: "cs")
    |> Changeset.cast_assoc(:named, [])
    |> Changeset.cast_assoc(:caretaker)
    |> Changeset.cast_assoc(:stereotype)
  end

  def list, do: repo().many(proload(from(u in Acl, as: :acl), [:named, :controlled, :stereotype, :caretaker]))

end
