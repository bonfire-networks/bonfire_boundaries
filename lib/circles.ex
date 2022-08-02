defmodule Bonfire.Boundaries.Circles do
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  import Bonfire.Boundaries.Integration
  import Bonfire.Boundaries.Queries
  import Ecto.Query
  import EctoSparkles

  alias Bonfire.Data.Identity.User
  alias Bonfire.Boundaries.Circles
  # alias Bonfire.Boundaries.Stereotyped
  alias Bonfire.Data.Identity.ExtraInfo
  alias Bonfire.Data.Identity.Named
  alias Bonfire.Data.AccessControl.{Circle, Encircle}
  alias Bonfire.Data.Identity.Caretaker
  alias Ecto.Changeset
  alias Pointers.{Changesets, Pointer}

  @default_q_opts [exclude_stereotypes: ["0KF1NEY0VD0N0TWANTT0HEARME"]] # don't show "others who silenced me" in circles

  # special built-in circles (eg, guest, local, activity_pub)
  def circles, do: Config.get([:circles])

  def get(slug) when is_atom(slug), do: Config.get([:circles])[slug]
  def get(id) when is_binary(id), do: get_tuple(id) |> elem_or(1, nil)

  def get!(slug) when is_atom(slug) do
    get(slug) || raise RuntimeError, message: "Missing default circle: #{inspect(slug)}"
  end

  def get_id(slug), do: Map.get(circles(), slug, %{})[:id]

  def get_id!(slug) when is_atom(slug), do: get!(slug).id

  def get_tuple(slug) when is_atom(slug) do
    {Config.get!([:circles, slug, :name]), Config.get!([:circles, slug, :id])}
  end
  def get_tuple(id) when is_binary(id) do
    Enum.find circles(), fn {_slug, c} ->
      c[:id] == id
    end
  end

  # def list, do: repo().many(from(u in Circle, left_join: named in assoc(u, :named), preload: [:named]))
  def list_by_ids(ids), do: repo().many(
    from(c in Circle,
      left_join: named in assoc(c, :named),
      where: c.id in ^ulid(ids),
      preload: [:named]
    ))

  def circle_ids(subjects) when is_list(subjects), do: subjects |> Enum.map(&circle_ids/1) |> Enum.uniq()
  def circle_ids(circle_name) when is_atom(circle_name) and not is_nil(circle_name), do: get_id(circle_name)
  def circle_ids(%{id: subject_id}), do: subject_id
  def circle_ids(subject_id) when is_binary(subject_id), do: subject_id
  def circle_ids(_), do: nil

  def to_circle_ids(subjects) do
    public = get_id(:guest)
    selected_circles = circle_ids(subjects)
    if public in selected_circles or :guest in selected_circles do # public/guests defaults to also being visible to local users and federating
      selected_circles ++ [
        get_id!(:local),
        get_id!(:activity_pub)
      ]
    else
      selected_circles
    end
    |> Enum.uniq()
  end

  # def create(%{}=attrs) do
  #   repo().insert(changeset(:create, attrs))
  # end

  @doc "Create a circle for the provided user (and with the user in the circle?)"
  def create(user, %{}=attrs) when is_map(user) or is_binary(user) do
    with {:ok, circle} <- repo().insert(changeset(:create,
    attrs
      |> input_to_atoms()
      |> deep_merge(%{
        caretaker: %{caretaker_id: ulid!(user)}
        # encircles: [%{subject_id: user.id}] # add myself to circle?
      })
    )) do
      # Bonfire.Boundaries.Boundaries.maybe_make_visible_for(user, circle) # make visible to myself - FIXME
      {:ok, circle}
    end
  end

  def create(:instance, %{}=attrs) do
    Bonfire.Boundaries.Fixtures.admin_circle()
    |> create(attrs)
  end

  def create(user, name) when is_binary(name) do
    create(user, %{named: %{name: name}})
  end

  def changeset(circle \\ %Circle{}, attrs)

  def changeset(:create, attrs), do: changeset(attrs)
    |> Changesets.cast_assoc(:caretaker, with: &Caretaker.changeset/2)

  def changeset(%Circle{} = circle, attrs) do
    Circle.changeset(circle, attrs)
    |> Changesets.cast(attrs, [])
    |> Changesets.cast_assoc(:named, with: &Named.changeset/2)
    |> Changesets.cast_assoc(:extra_info, with: &ExtraInfo.changeset/2)
    |> Changesets.cast_assoc(:encircles, with: &Encircle.changeset/2)
  end

  def changeset(:update, circle, params) do

    # Ecto doesn't like mixed keys so we convert them all to strings
    params = for {k, v} <- params, do: {to_string(k), v}, into: %{}
    # debug(params)

    changeset(circle, params)
  end

  @doc """
  Lists the circles that we are permitted to see.
  """
  def is_encircled_by?(subject, circle) when is_atom(circle), do: is_encircled_by?(subject, [get_id!(circle)])
  def is_encircled_by?(subject, circle) when not is_list(circle), do: is_encircled_by?(subject, [circle])
  def is_encircled_by?(subject, circles), do: repo().exists?(is_encircled_by_q(subject, circles))

  #@doc "query for `list_visible`"
  defp is_encircled_by_q(subject, circles) do
    from(encircle in Encircle, as: :encircle)
    |> where([encircle: encircle],
      encircle.subject_id == ^ulid(subject)
      and encircle.circle_id in ^(
        ulid(circles)
        # |> info("circle_ids")
      )
    )
  end


  ## invariants:
  ## * Created circles will have the user as a caretaker


  @doc """
  Lists the circles that we are permitted to see.
  """
  def list_visible(user, opts \\ []), do: repo().many(list_visible_q(user, opts ++ @default_q_opts))

  @doc "query for `list_visible`"
  def list_q(user, opts \\ []) do
    from(circle in Circle, as: :circle)
    |> proload([:named, :extra_info, :caretaker, stereotyped: {"stereotype_", [:named]}])
    |> where([circle, stereotyped: stereotyped], circle.id not in ^e(opts, :exclude_stereotypes, []) and (is_nil(stereotyped.id) or stereotyped.stereotype_id not in ^e(opts, :exclude_stereotypes, [])))
  end

  @doc "query for `list_visible`"
  def list_visible_q(user, opts \\ []) do
    list_q(user, opts)
    |> boundarise(circle.id, opts ++ [current_user: user])
  end

  @doc """
  Lists the circles we are the registered caretakers of that we are
  permitted to see. If any circles are created without permitting the
  user to see them, they will not be shown.
  """
  def list_my(user, opts \\ []), do: repo().many(list_my_q(user, opts ++ @default_q_opts))

  def list_my_with_counts(user, opts \\ []) do
    list_my_q(user, opts ++ @default_q_opts)
    |> join(:left, [circle], encircles in subquery(from ec in Encircle,
      group_by: ec.circle_id,
      select: %{circle_id: ec.circle_id, count: count()}
    ), on: encircles.circle_id == circle.id, as: :encircles)
    |> select_merge([encircles: encircles], %{encircles_count: encircles.count})
    |> order_by([encircles: encircles], desc_nulls_last: encircles.count)
    |> repo().many()
  end

  @doc "query for `list_my`"
  def list_my_q(user, opts \\ []) when not is_nil(user) do
    user
    # |> dump
    |> list_q(opts)
    |> where([circle, caretaker: caretaker], caretaker.caretaker_id == ^ulid!(user) or (circle.id in ^e(opts, :extra_ids_to_include, [])))
  end

  def list_my_defaults(_user \\ nil) do
    # TODO make configurable
    Enum.map([:guest, :local, :activity_pub], &Circles.get_tuple/1)
  end

  def get_for_caretaker(id, caretaker, opts \\ []) do
    with {:ok, circle} <- repo().single(get_for_caretaker_q(id, caretaker, opts ++ @default_q_opts)) do
      {:ok, circle}
    else
      {:error, :not_found} ->
        if is_admin?(caretaker), do: repo().single(get_for_caretaker_q(id, Bonfire.Boundaries.Fixtures.admin_circle(), opts ++ @default_q_opts)), else: {:error, :not_found}
    end
  end

  def get_stereotype_circles(subject, stereotypes) when is_list(stereotypes) do
    stereotypes = Enum.map(stereotypes, &Bonfire.Boundaries.Circles.get_id!/1)

    list_my_q(subject, skip_boundary_check: true) # skip boundaries since we should only use this query internally
    |> where(
      [circle: circle, stereotyped: stereotyped],
      stereotyped.stereotype_id in ^ulid(stereotypes)
    )
    |> repo().all()
  end
  def get_stereotype_circles(subject, stereotype), do: get_stereotype_circles(subject, [stereotype])

  @doc "query for `get`"
  def get_for_caretaker_q(id, caretaker, opts \\ []) do
    list_q(caretaker, opts)
    # |> reusable_join(:inner, [circle: circle], caretaker in assoc(circle, :caretaker), as: :caretaker)
    |> where([circle: circle, caretaker: caretaker], circle.id == ^ulid!(id) and caretaker.caretaker_id == ^ulid!(caretaker))
  end

  def edit(%Circle{} = circle, %User{} = user, params) do
    circle = circle
    |> repo().maybe_preload([:encircles, :named, :extra_info])

    params
    |> input_to_atoms()
    |> Changesets.put_id_on_mixins([:named, :extra_info], circle)
    # |> input_to_atoms()
    # |> Map.update(:named, nil, &Map.put(&1, :id, ulid(circle)))
    # |> Map.update(:extra_info, nil, &Map.put(&1, :id, ulid(circle)))
    |> changeset(:update, circle, ...)
    |> repo().update()
  end

  def edit(id, %User{} = user, params) do
    with {:ok, circle} <- get_for_caretaker(id, user) do
      edit(circle, user, params)
    end
  end

  def add_to_circles(subject, circles) when is_list(circles) do
    Enum.map(circles, &add_to_circles(subject, &1)) # TODO: optimise
  end
  def add_to_circles(subject, circle) when not is_nil(circle) do
    repo().insert(Encircle.changeset(%{circle_id: ulid(circle), subject_id: ulid(subject)}))
  end

  def remove_from_circles(subject, circles) when is_nil(circles) or length(circles)==0, do: error("No circle ID provided, so could not remove")
  def remove_from_circles(subject, circles) when is_list(circles) do
    from(e in Encircle, where: e.subject_id == ^ulid(subject) and e.circle_id in ^ulid(circles))
    |> repo().delete_all
  end
  def remove_from_circles(subject, circle) do
    remove_from_circles(subject, [circle])
  end

  @doc """
  Fully delete the circle, including membership and boundary information. This will affect all objects previously shared with members of this circle.
  """
  def delete(%Circle{}=circle, opts) do
    assocs = [:encircles, :caretaker, :named, :extra_info, :stereotyped]

    Bonfire.Social.Objects.maybe_generic_delete(Circle, circle, current_user: current_user(opts), delete_associations: assocs)
  end
  def delete(id, opts) do
    with {:ok, circle} <- get_for_caretaker(id, current_user(opts)) do
      delete(circle, opts)
    end
  end

end
