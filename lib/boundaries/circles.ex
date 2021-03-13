defmodule Bonfire.Boundaries.Circles do

  alias Bonfire.Data.Social.Circle
  import Bonfire.Boundaries.Integration
  import Ecto.Query

  def circles do
    Bonfire.Common.Config.get!(:default_circles)
  end

  def circle_names do
    Bonfire.Common.Config.get!(:circle_names)
  end

  def circles_fixture do
    Enum.map(circles(), fn {k, v} -> %{id: v} end)
  end

  def circles_named_fixture do
    Enum.map(circles(), fn {k, v} -> %{id: v, name: circle_names()[k]} end)
  end

  def list, do: repo().all(from(u in Circle))

  def create(%{}=attrs) do
    repo().insert(changeset(:create, attrs))
  end

  def changeset(:create, attrs), do: Circle.changeset(attrs)

end
