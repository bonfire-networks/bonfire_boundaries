defmodule Bonfire.Boundaries.Circles do
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  import Bonfire.Boundaries.Integration
  import Bonfire.Boundaries.Queries
  import Ecto.Query
  import EctoSparkles

  alias Bonfire.Data.Identity.User
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Stereotyped
  alias Bonfire.Data.Identity.Named
  alias Bonfire.Data.AccessControl.{Circle, Encircle}
  alias Bonfire.Data.Identity.Caretaker
  alias Ecto.Changeset

  # special built-in circles (eg, guest, local, activity_pub)
  def circles, do: Bonfire.Common.Config.get([:circles])

  def get(slug) when is_atom(slug), do: Bonfire.Common.Config.get([:circles])[slug]
  def get(id) when is_binary(id), do: get_tuple(id) |> elem_or(1, nil)

  def get!(slug) when is_atom(slug) do
    get(slug) || raise RuntimeError, message: "Missing default circle: #{inspect(slug)}"
  end

  def get_id(slug), do: Map.get(circles(), slug, %{})[:id]

  def get_id!(slug) when is_atom(slug), do: get!(slug).id

  def get_tuple(slug) when is_atom(slug) do
    {Bonfire.Common.Config.get!([:circles, slug, :name]), Bonfire.Common.Config.get!([:circles, slug, :id])}
  end
  def get_tuple(id) when is_binary(id) do
    Enum.find circles(), fn {_slug, c} ->
      c[:id] == id
    end
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

  @doc """
  Lists the circles that we are permitted to see.
  """
  def is_encircled_by?(subject, circle) when is_atom(circle), do: is_encircled_by?(subject, [get_id!(circle)])
  def is_encircled_by?(subject, circle) when not is_list(circle), do: is_encircled_by?(subject, [circle])
  def is_encircled_by?(subject, circles), do: repo().exists?(is_encircled_by_q(subject, circles))

  @doc "query for `list_visible`"
  defp is_encircled_by_q(subject, circles) do
    from(encircle in Encircle, as: :encircle)
    |> where([encircle: encircle],
      encircle.subject_id == ^ulid(subject)
      and encircle.circle_id in ^(
        ulid(circles)
        # |> dump("circle_ids")
      )
    )
  end


  ## invariants:
  ## * Created circles will have the user as a caretaker


  @doc "Create a circle for the provided user (and with the user in the circle?)"
  def create(%User{}=user, name \\ nil, %{}=attrs \\ %{}) do
    with {:ok, circle} <- repo().insert(changeset(:create,
    user,
    attrs
      |> deep_merge(%{
        named: %{name: name},
        caretaker: %{caretaker_id: user.id}
        # encircles: [%{subject_id: user.id}] # add myself to circle?
      })
    )) do
      # Bonfire.Boundaries.Boundaries.maybe_make_visible_for(user, circle) # make visible to myself - FIXME
      {:ok, circle}
    end
  end


  @doc """
  Lists the circles that we are permitted to see.
  """
  def list_visible(user, opts \\ []), do: repo().many(list_visible_q(user, opts))

  @doc "query for `list_visible`"
  def list_visible_q(user, opts \\ []) do
    from(circle in Circle, as: :circle)
    |> boundarise(circle.id, opts ++ [current_user: user])
    |> proload([:named, :caretaker, stereotyped: {"stereotype_", [:named]}])
  end

  @doc """
  Lists the circles we are the registered caretakers of that we are
  permitted to see. If any circles are created without permitting the
  user to see them, they will not be shown.
  """
  def list_my(user, opts \\ []), do: repo().many(list_my_q(user, opts))

  @doc "query for `list_my`"
  def list_my_q(user, opts \\ []) when not is_nil(user) do
    user
    # |> dump
    |> list_visible_q(opts)
    |> where([caretaker: caretaker], caretaker.caretaker_id == ^ulid(user))
  end

  def list_my_defaults(_user \\ nil) do
    # TODO make configurable
    Enum.map([:guest, :local, :activity_pub], &Circles.get_tuple/1)
  end

  def get(id, %User{}=user) do
    repo().single(get_q(id, user))
  end

  def get_stereotype_circles(subject, stereotypes) when is_list(stereotypes) do
    stereotypes = Enum.map(stereotypes, &Bonfire.Boundaries.Circles.get_id!/1)

    list_my_q(subject, skip_boundary_check: true) # skip boundaries since we should only use this query internally
    |> where([circle: circle, stereotyped: stereotyped], stereotyped.stereotype_id in ^ulid(stereotypes))
    |> dump()
    |> repo().all()
  end

  @doc "query for `get`"
  def get_q(id, user) do
    list_visible_q(user)
    |> join(:inner, [circle: circle], caretaker in assoc(circle, :caretaker), as: :caretaker)
    |> where([circle: circle, caretaker: caretaker], circle.id == ^id and caretaker.caretaker_id == ^ulid(user))
  end

  def update(id, %User{} = user, params) do
    with {:ok, circle} <- get(id, user)
    |> repo().maybe_preload([:encircles]) do

      repo().update(changeset(:update, circle, params))
    end
  end

  def add_to_circles(subject, circles) when is_list(circles) do
    Enum.map(circles, &add_to_circle(subject, &1))
  end
  def add_to_circle(subject, circle) do
    repo().insert(Encircle.changeset(%{circle_id: ulid(circle), subject_id: ulid(subject)}))
  end

  def changeset(:create, %User{}=_user, attrs) do
    Circles.changeset(:create, attrs)
  end

  def changeset(:update, circle, params) do

    # Ecto doesn't like mixed keys so we convert them all to strings
    params = for {k, v} <- params, do: {to_string(k), v}, into: %{}
    # debug(params)

    circle
    |> Circles.changeset(params)
  end

end
