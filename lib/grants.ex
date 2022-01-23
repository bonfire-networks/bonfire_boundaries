defmodule Bonfire.Boundaries.Grants do
  @moduledoc """
  a grant applies to a subject
  """
  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Boundaries.Accesses
  alias Bonfire.Boundaries.Circles
  alias Ecto.Changeset

  import Bonfire.Boundaries
  use Bonfire.Common.Utils
  import Ecto.Query

  def create(%{}=attrs) when not is_struct(attrs) do
    repo().insert(changeset(attrs))
  end

  def changeset(grant \\ %Grant{}, attrs) do
    Grant.changeset(grant, attrs)
    |> Changeset.cast_assoc(:caretaker)
  end

end
