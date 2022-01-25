defmodule Bonfire.Boundaries.Circles do

  alias Bonfire.Data.Identity.Named
  alias Bonfire.Data.AccessControl.{Circle, Encircle}
  alias Bonfire.Data.Identity.Caretaker

  import Bonfire.Boundaries
  import Ecto.Query
  alias Ecto.Changeset

  # special built-in circles (eg, guest, local, activity_pub)
  def circles, do: Bonfire.Common.Config.get([:circles])

  def get(slug) when is_atom(slug), do: Bonfire.Common.Config.get([:circles])[slug]

  def get!(slug) when is_atom(slug) do
    get(slug) || raise RuntimeError, message: "Missing default circle: #{inspect(slug)}"
  end

  def get_id(slug), do: Map.get(circles(), slug, %{})[:id]

  def get_id!(slug) when is_atom(slug), do: get!(slug).id

  # def get_tuple(id) when is_binary(id) do
  #   case by_id(id) do
  #     {slug, _} -> get_tuple(slug)
  #     _ -> nil  # TODO
  #   end
  # end

  def get_tuple(slug) when is_atom(slug) do
    {Bonfire.Common.Config.get!([:circles, slug, :name]), Bonfire.Common.Config.get!([:circles, slug, :id])}
  end

  def list, do: repo().many(from(u in Circle, left_join: named in assoc(u, :named), preload: [:named]))

  def circle_ids(subjects) when is_list(subjects), do: subjects |> Enum.map(&circle_ids/1) |> Enum.uniq()
  def circle_ids(circle_name) when is_atom(circle_name) and not is_nil(circle_name), do: get_id(circle_name)
  def circle_ids(%{id: subject_id}), do: subject_id
  def circle_ids(subject_id) when is_binary(subject_id), do: subject_id
  def circle_ids(_), do: nil

  def to_circle_ids(subjects) do
    public = get_id(:guest)
    selected_circles = circle_ids(subjects)
    if public in selected_circles do # public/guests defaults to also being visible to local users and federating
      selected_circles ++ [
        get_id!(:local),
        get_id!(:activity_pub)
      ]
    else
      selected_circles
    end
    |> Enum.uniq()
  end

  def create(%{}=attrs) do
    repo().insert(changeset(:create, attrs))
  end

  def changeset(circle \\ %Circle{}, attrs)

  def changeset(:create, attrs), do: changeset(attrs)
    |> Changeset.cast_assoc(:caretaker, with: &Caretaker.changeset/2)

  def changeset(%Circle{} = circle, attrs), do: Circle.changeset(circle, attrs)
    |> Changeset.cast_assoc(:named, with: &Named.changeset/2)
    |> Changeset.cast_assoc(:encircles, with: &Encircle.changeset/2)

end