defmodule Bonfire.Boundaries.Controlleds do

  alias Bonfire.Data.AccessControl.Controlled
  import Bonfire.Boundaries.Integration

  def create(%{}=attrs) when not is_struct(attrs) do
    repo().insert(changeset(attrs))
  end

  def changeset(c \\ %Controlled{}, attrs) do
    Controlled.changeset(c, attrs)
  end

end
