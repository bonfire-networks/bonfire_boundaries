defmodule Bonfire.Boundaries.Circles do

  alias Bonfire.Data.Social.Named
  alias Bonfire.Data.Social.Circle
  alias Bonfire.Data.Social.Encircle
  alias Bonfire.Data.Identity.Caretaker

  import Bonfire.Boundaries.Integration
  import Ecto.Query
  alias Ecto.Changeset

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

  def list, do: repo().all(from(u in Circle, left_join: named in assoc(u, :named), preload: [:named]))

  def create(%{}=attrs) do
    repo().insert(changeset(:create, attrs))
  end

  def changeset(:create, attrs), do: changeset(attrs)
    |> Changeset.cast_assoc(:caretaker, with: &Caretaker.changeset/2)

  def changeset(circle \\ %Circle{}, attrs), do: Circle.changeset(circle, attrs)
    |> Changeset.cast_assoc(:named, with: &Named.changeset/2)
    |> Changeset.cast_assoc(:encircles, with: &Encircle.changeset/2)

end
