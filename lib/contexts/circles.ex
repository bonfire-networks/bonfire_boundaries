defmodule Bonfire.Boundaries.Circles do
  @moduledoc """
  Functions to create, query, and manage circles, which are used to group users (for the purpose of control access to various resources).

  Circles are a way of categorizing users. Each user can have their own set of circles to categorize other users. Circles allow a user to group work colleagues differently from friends for example, and to allow different interactions for users in each circle or limit content visibility on a per-item basis.

  > Circles are a tool that can be used to establish relationships. They are representations of multifaceted relationships that you have with people in your life. Circles can help you understand the different levels of intimacy and trust that you have with different people, as well the different contexts or topics which are relevant to particular relationships, and can help build stronger, healthier relationships.

  > In Bonfire, you can define circles based on your unique style of relationships and interests. For example, you might create a circle for your colleagues, which can help you keep track of work-related content and collaborate with them more efficiently. You could also have a locals circle, with which you may share and discover local events, news, and recommendations. You might also create a comrades circle, to stay connected with fellow activists and organise around shared goals. Finally, you could create a happy hour circle, to coordinate social gatherings with local friends or colleagues, and the crew for your inner circle. With circles, you have the flexibility to manage your relationships and social activities in a way that makes sense for you.

  The corresponding Ecto schema are `Bonfire.Data.AccessControl.Circle` and `Bonfire.Data.AccessControl.Encircle` which is defined in a [seperate repo](https://github.com/bonfire-networks/bonfire_data_access_control).

  """

  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  import Bonfire.Boundaries.Queries
  import Ecto.Query
  import EctoSparkles

  alias Bonfire.Data.Identity.User
  alias Bonfire.Boundaries.Circles
  # alias Bonfire.Data.AccessControl.Stereotyped
  alias Bonfire.Data.Identity.ExtraInfo
  alias Bonfire.Data.Identity.Named
  alias Bonfire.Data.AccessControl.Circle
  alias Bonfire.Data.AccessControl.Encircle

  alias Bonfire.Data.Identity.Caretaker
  # alias Ecto.Changeset
  alias Needle.Changesets
  # alias Needle.Pointer

  # don't show "others who silenced me" in circles
  @reverse_stereotypes ["0KF1NEY0VD0N0TWANTT0HEARME"]
  @default_q_opts [exclude_circles: @reverse_stereotypes]
  @block_stereotypes ["7N010NGERWANTT011STENT0Y0V", "7N010NGERC0NSENTT0Y0VN0WTY"]
  # @exclude_stereotypes ["7N010NGERWANTT011STENT0Y0V", "7N010NGERC0NSENTT0Y0VN0WTY", "4THEPE0P1ES1CH00SET0F0110W", "7DAPE0P1E1PERM1TT0F0110WME"]
  @follow_stereotypes [
    "7DAPE0P1E1PERM1TT0F0110WME",
    "4THEPE0P1ES1CH00SET0F0110W"
  ]

  @doc """
  Returns a list of special built-in circles (e.g., guest, local, activity_pub).
  """
  def circles, do: Config.get([:circles], %{})

  @doc """
  Returns a list of stereotype circle IDs.
  """
  def stereotype_ids do
    circles()
    |> Map.values()
    |> Enum.filter(&e(&1, :stereotype, nil))
    |> Enum.map(& &1.id)
  end

  @doc """
  Returns a list of stereotype IDs for a specific category.

  ## Examples

      iex> Bonfire.Boundaries.Circles.stereotypes(:follow)

      iex> Bonfire.Boundaries.Circles.stereotypes(:block)
  """
  def stereotypes(:follow), do: @follow_stereotypes
  def stereotypes(:block), do: @block_stereotypes ++ @reverse_stereotypes

  @doc """
  Returns a list of built-in circle IDs.
  """
  def built_in_ids do
    circles()
    |> Map.values()
    |> Enums.ids()
  end

  @doc """
  Checks if a circle is a built-in circle.
  """
  def is_built_in?(circle) do
    # debug(acl)
    uid(circle) in built_in_ids()
  end

  @doc """
  Checks if a circle is a stereotype circle.

  ## Examples

      iex> Bonfire.Boundaries.Circles.is_stereotype?("7DAPE0P1E1PERM1TT0F0110WME")
      true

      iex> Bonfire.Boundaries.Circles.is_stereotype?("custom_circle_id")
      false
  """
  def is_stereotype?(acl) do
    uid(acl) in stereotype_ids()
  end

  @doc """
  Retrieves a circle by its slug or ID.

  ## Examples

      iex> Bonfire.Boundaries.Circles.get(:guest)
      %{id: "guest_circle_id", name: "Guest"}

      iex> Bonfire.Boundaries.Circles.get("circle_id")
      %Circle{id: "circle_id", name: "Custom Circle"}
  """
  def get(slug) when is_atom(slug), do: circles()[slug]
  def get(id) when is_binary(id), do: get_tuple(id) |> Enums.maybe_elem(1)

  def get!(slug) when is_atom(slug) do
    get(slug) ||
      raise RuntimeError, message: "Missing built-in circle: #{inspect(slug)}"
  end

  @doc """
  Retrieves the ID of a circle by its slug.

  ## Examples

      iex> Bonfire.Boundaries.Circles.get_id(:guest)
      "guest_circle_id"

      iex> Bonfire.Boundaries.Circles.get_id(:nonexistent)
      nil
  """
  def get_id(slug), do: Map.get(circles(), slug, %{})[:id]

  def get_id!(slug) when is_atom(slug), do: get!(slug).id

  @doc """
  Retrieves a tuple containing the name and ID of a circle by its slug or ID.

  ## Examples

      iex> Bonfire.Boundaries.Circles.get_tuple(:guest)
      {"Guest", "guest_circle_id"}

      iex> Bonfire.Boundaries.Circles.get_tuple("circle_id")
      {:my_circle, %{id: "circle_id", name: "My Circle"}}
  """
  def get_tuple(slug) when is_atom(slug) do
    {Config.get!([:circles, slug, :name]), Config.get!([:circles, slug, :id])}
  end

  def get_tuple(id) when is_binary(id) do
    Enum.find(circles(), fn {_slug, c} ->
      c[:id] == id
    end)
  end

  @doc """
  Lists default circles for a user.

  ## Examples

      iex> Bonfire.Boundaries.Circles.list_my_defaults()
      [{"Guest", "guest_circle_id"}, {"Local", "local_circle_id"}, {"ActivityPub", "activity_pub_circle_id"}]
  """
  def list_my_defaults(_user \\ nil) do
    # TODO make configurable
    Enum.map([:guest, :local, :activity_pub], &Circles.get_tuple/1)
  end

  @doc """
  Lists all built-in circles.

  ## Examples

      iex> Bonfire.Boundaries.Circles.list_built_ins()
      [%Circle{id: "guest_circle_id", name: "Guest"}, %Circle{id: "local_circle_id", name: "Local"}]
  """
  def list_built_ins() do
    Enum.map(circles(), fn {_slug, %{id: id}} ->
      id
    end)
    |> list_by_ids()
  end

  # def list, do: repo().many(from(u in Circle, left_join: named in assoc(u, :named), preload: [:named]))

  @doc """
  Lists circles by their IDs.

  ## Examples

      iex> Bonfire.Boundaries.Circles.list_by_ids(["circle_id1", "circle_id2"])
      [%Circle{id: "circle_id1", name: "Circle 1"}, %Circle{id: "circle_id2", name: "Circle 2"}]
  """
  def list_by_ids(ids),
    do:
      repo().many(
        from(c in Circle,
          left_join: named in assoc(c, :named),
          where: c.id in ^Types.uids(ids),
          preload: [:named]
        )
        # |> query_with_counts() 
      )

  @doc """
  Converts a list of circles to circle IDs.

  ## Examples

      iex> Bonfire.Boundaries.Circles.circle_ids([:guest, :local])
      ["guest_circle_id", "local_circle_id"]

      iex> Bonfire.Boundaries.Circles.circle_ids(%{id: "user_id"})
      "user_id"
  """
  def circle_ids(subjects) when is_list(subjects),
    do: subjects |> Enum.flat_map(&circle_ids/1) |> Enum.uniq()

  def circle_ids(circle_name)
      when is_atom(circle_name) and not is_nil(circle_name),
      do: [get_id(circle_name)]

  def circle_ids(%{id: subject_id}), do: [subject_id]
  def circle_ids(subject_id) when is_binary(subject_id), do: [uid(subject_id)]
  def circle_ids(_), do: []

  @doc """
  Converts a list of circles to circle IDs, including adding default circles (such as local or activity_pub when relevant)

  ## Examples

      iex> Bonfire.Boundaries.Circles.to_circle_ids([:guest, :custom])
      ["guest_circle_id", "custom_circle_id", "local_circle_id", "activity_pub_circle_id"]
  """
  def to_circle_ids(subjects) do
    public = get_id(:guest)
    selected_circles = circle_ids(subjects)
    # public/guests defaults to also being visible to local users and federating
    if public in selected_circles or :guest in selected_circles do
      selected_circles ++
        [
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

  @doc """
  Creates a new circle for the provided user.

  ## Examples

      iex> Bonfire.Boundaries.Circles.create(caretaker, %{named: %{name: "My Circle"}})
      {:ok, %Circle{id: "new_circle_id", name: "My Circle"}}
  """
  def create(caretaker, %{} = attrs) when is_map(caretaker) or is_binary(caretaker) do
    with {:ok, circle} <-
           repo().insert(
             changeset(
               :create,
               attrs
               |> input_to_atoms()
               |> deep_merge(%{
                 caretaker: %{caretaker_id: uid!(caretaker)}
                 # encircles: [%{subject_id: user.id}] # add myself to circle?
               })
             )
           ) do
      # Bonfire.Boundaries.Boundaries.maybe_make_visible_for(user, circle) # make visible to myself - FIXME
      {:ok, circle}
    end
  end

  def create(:instance, %{} = attrs) do
    create(
      Bonfire.Boundaries.Scaffold.Instance.admin_circle(),
      attrs
    )
  end

  def create(caretaker, name) when is_binary(name) do
    create(caretaker, %{named: %{name: name}})
  end

  def changeset(circle \\ %Circle{}, attrs)

  def changeset(:create, attrs),
    do:
      changeset(attrs)
      |> Changesets.cast_assoc(:caretaker, with: &Caretaker.changeset/2)

  def changeset(%Circle{} = circle, attrs) do
    Circle.changeset(circle, attrs)
    |> Changesets.cast(attrs, [])
    |> Changesets.cast_assoc(:named, with: &Named.changeset/2)
    |> Changesets.cast_assoc(:stereotyped, with: &Stereotyped.changeset/2)
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
  Checks if a subject is encircled by a circle or list of circles.

  ## Examples

      iex> Bonfire.Boundaries.Circles.is_encircled_by?(user, circle)
      true

      iex> Bonfire.Boundaries.Circles.is_encircled_by?(user, [circle1, circle2])
      false
  """
  def is_encircled_by?(subject, circle)
      when is_nil(subject) or is_nil(circle) or subject == [] or circle == [],
      do: nil

  def is_encircled_by?(subject, circle) when is_atom(circle) and not is_nil(circle),
    do: is_encircled_by?(subject, get_id!(circle))

  def is_encircled_by?(subject, %{__struct__: schema, display_hostname: display_hostname})
      when schema == Bonfire.Data.ActivityPub.Peer do
    with {:ok, circle} <-
           get_by_name(
             display_hostname,
             Bonfire.Boundaries.Scaffold.Instance.activity_pub_circle()
           )
           |> debug("circle for peer") do
      is_encircled_by?(subject, circle)
    else
      _ ->
        nil
    end
  end

  def is_encircled_by?(subject, circles)
      when is_list(circles) or is_binary(circles) or is_map(circles),
      do: repo().exists?(is_encircled_by_q(subject, circles))

  # @doc "query for `is_encircled_by`"
  defp is_encircled_by_q(subject, circles) do
    encircled_by_q(subject)
    |> where(
      [encircle: encircle],
      encircle.circle_id in ^uids(circles)
    )
  end

  defp encircled_by_q(subject) do
    from(encircle in Encircle, as: :encircle)
    |> where(
      [encircle: encircle],
      encircle.subject_id in ^uids(subject)
    )
  end

  def preload_encircled_by(subject, circles, opts \\ []) do
    circles
    |> repo().preload([encircles: encircled_by_q(subject)], opts)

    # |> debug()
  end

  ## invariants:
  ## * Created circles will have the user as a caretaker

  @doc """
  Retrieves a circle for a caretaker by ID.

  ## Examples

      iex> Bonfire.Boundaries.Circles.get_for_caretaker("circle_id", user)
      {:ok, %Circle{id: "circle_id", name: "My Circle"}}
  """
  def get_for_caretaker(id, caretaker, opts \\ []) do
    opts = opts ++ @default_q_opts

    with {:ok, circle} <-
           repo().single(query_my_by_id(id, caretaker, opts)) do
      {:ok, circle}
    else
      {:error, :not_found} ->
        if Bonfire.Boundaries.can?(current_account(opts) || caretaker, :assign, :instance) ||
             opts[:scope] == :instance_wide,
           do:
             repo().single(
               query_my_by_id(
                 id,
                 Bonfire.Boundaries.Scaffold.Instance.admin_circle(),
                 opts
               )
             ),
           else: {:error, :not_found}
    end
  end

  def get_for_instance(id, opts \\ []) do
    get_for_caretaker(id, Bonfire.Boundaries.Scaffold.Instance.admin_circle(), opts)
  end

  @doc """
  Retrieves a circle by name for a caretaker.

  ## Examples

      iex> Bonfire.Boundaries.Circles.get_by_name("My Circle", user)
      {:ok, %Circle{id: "circle_id", name: "My Circle"}}
  """
  def get_by_name(name, caretaker) do
    repo().single(
      query_basic_my(caretaker || Bonfire.Boundaries.Scaffold.Instance.admin_circle(), name: name)
    )
  end

  @doc """
  Retrieves stereotype circles for a subject.

  ## Examples

      iex> Bonfire.Boundaries.Circles.get_stereotype_circles(user, [:follow, :block])
      [%Circle{id: "follow_circle_id", name: "Follow"}, %Circle{id: "block_circle_id", name: "Block"}]
  """

  # def get_stereotype_circles(%{__struct__: schema, display_hostname: display_hostname}, stereotypes) when schema == Bonfire.Data.ActivityPub.Peer do
  #   raise "Instance stereotypes not implemented"
  # end

  def get_stereotype_circles(subject, stereotypes)
      when is_list(stereotypes) and stereotypes != [] do
    stereotypes =
      Enum.map(stereotypes, &Bonfire.Boundaries.Circles.get_id!/1)
      |> uids()

    if stereotypes == [] do
      []
    else
      # skip boundaries since we should only use this query internally
      query_my(subject, skip_boundary_check: true)
      |> where(
        [circle: circle, stereotyped: stereotyped],
        stereotyped.stereotype_id in ^stereotypes
      )
      |> repo().all()
    end
  end

  def get_stereotype_circles(subject, stereotype)
      when not is_nil(stereotype) and stereotype != [],
      do: get_stereotype_circles(subject, [stereotype])

  def get_or_create_stereotype_circle(caretaker, stereotype) do
    case get_stereotype_circles(caretaker, [stereotype]) do
      [] ->
        create_stereotype_circle(caretaker, stereotype)

      [existing] ->
        {:ok, existing}

      other ->
        error(other, "Unexpected number of stereotypes")
    end
  end

  def create_stereotype_circle(caretaker, stereotype) do
    create(caretaker, %{
      stereotyped: %{stereotype_id: Bonfire.Boundaries.Circles.get_id!(stereotype)}
    })
  end

  @doc """
  Lists visible circles for a user.

  ## Examples

      iex> Bonfire.Boundaries.Circles.list_visible(user)
      [%Circle{id: "circle_id1", name: "Circle 1"}, %Circle{id: "circle_id2", name: "Circle 2"}]
  """
  def list_visible(user, opts \\ []),
    do: repo().many(query_visible(user, opts ++ @default_q_opts))

  @doc """
  Lists circles owned by a user.

  Includes circles we are the registered caretakers of that we are
  permitted to see. If any circles are created without permitting the
  user to see them, they will not be shown.

  ## Examples

      iex> Bonfire.Boundaries.Circles.list_my(user)
      [%Circle{id: "circle_id1", name: "My Circle 1"}, %Circle{id: "circle_id2", name: "My Circle 2"}]
  """
  def list_my(user, opts \\ []),
    do: repo().many(query_my(user, opts ++ @default_q_opts))

  @doc """
  Lists circles owned by a user and global/built-in circles.

  ## Examples

      iex> Bonfire.Boundaries.Circles.list_my_with_global(user)
      [%Circle{id: "circle_id1", name: "My Circle"}, %Circle{id: "global_circle_id", name: "Global Circle"}]
  """
  def list_my_with_global(user, opts \\ []) do
    list_my(
      user,
      opts ++
        [
          extra_ids_to_include:
            opts[:global_circles] || Bonfire.Boundaries.Scaffold.Instance.global_circles()
        ]
    )
  end

  @doc """
  Lists circles owned by a user with member counts.

  ## Examples

      iex> Bonfire.Boundaries.Circles.list_my_with_counts(user)
      [%Circle{id: "circle_id1", name: "My Circle", encircles_count: 5}]
  """
  def list_my_with_counts(user, opts \\ []) do
    query_my(user, opts ++ @default_q_opts)
    |> query_with_counts()
    |> many(opts[:paginate?], opts)
  end

  defp query_with_counts(query) do
    query
    |> join(
      :left,
      [circle],
      encircles in subquery(
        from(ec in Encircle,
          group_by: ec.circle_id,
          select: %{circle_id: ec.circle_id, count: count()}
        )
      ),
      on: encircles.circle_id == circle.id,
      as: :encircles
    )
    |> select_merge([encircles: encircles], %{encircles_count: encircles.count})

    # |> order_by([encircles: encircles], desc_nulls_last: encircles.count) # FIXME: custom order messes with pagination
  end

  @doc """
  Generates a query for circles 

  ## Examples

      iex> Bonfire.Boundaries.Circles.query(exclude_built_ins: true)
  """
  def query(opts \\ []) do
    exclude_circles =
      e(opts, :exclude_circles, []) ++
        if opts[:exclude_built_ins],
          do: built_in_ids(),
          else:
            if(opts[:exclude_stereotypes],
              do: stereotype_ids(),
              else:
                if(opts[:exclude_block_stereotypes],
                  do: @block_stereotypes,
                  else: []
                )
            )

    from(circle in Circle, as: :circle)
    |> proload([
      :named,
      :extra_info,
      :caretaker,
      stereotyped: {"stereotype_", [:named]}
    ])
    |> where(
      [circle, stereotyped: stereotyped],
      circle.id not in ^exclude_circles and
        (is_nil(stereotyped.id) or
           stereotyped.stereotype_id not in ^exclude_circles)
    )
    |> maybe_by_name(opts[:name])
    |> maybe_search(opts[:search])
  end

  defp maybe_by_name(query, text) when is_binary(text) and text != "" do
    query
    |> where(
      [named: named],
      named.name == ^text
    )
  end

  defp maybe_by_name(query, _), do: query

  defp maybe_search(query, text) when is_binary(text) and text != "" do
    query
    |> where(
      [named: named, stereotype_named: stereotype_named],
      ilike(named.name, ^"#{text}%") or
        ilike(named.name, ^"% #{text}%") or
        ilike(stereotype_named.name, ^"#{text}%") or
        ilike(stereotype_named.name, ^"% #{text}%")
    )
  end

  defp maybe_search(query, _), do: query

  @doc """
  Generates a query for visible circles for a user.

  ## Examples

      iex> Bonfire.Boundaries.Circles.query_visible(user)
      #Ecto.Query<...>
  """
  def query_visible(user, opts \\ []) do
    opts = to_options(opts)

    query(opts)
    |> boundarise(circle.id, opts ++ [current_user: user])
  end

  defp query_basic(opts) do
    from(circle in Circle, as: :circle)
    |> proload([
      :named,
      :caretaker
    ])
    |> maybe_by_name(opts[:name])
    |> maybe_search(opts[:search])
  end

  defp query_basic_my(user, opts \\ []) when not is_nil(user) do
    query_basic(opts)
    |> where(
      [circle, caretaker: caretaker],
      caretaker.caretaker_id == ^uid!(user) or
        circle.id in ^e(opts, :extra_ids_to_include, [])
    )
  end

  @doc """
  Generates a query for circles owned by a user.

  ## Examples

      iex> Bonfire.Boundaries.Circles.query_my(user)
  """
  def query_my(caretaker, opts \\ [])

  def query_my(caretaker, opts)
      when (is_binary(caretaker) or is_map(caretaker) or is_list(caretaker)) and caretaker != [] do
    opts = to_options(opts)

    query(opts)
    |> where(
      [circle, caretaker: caretaker],
      caretaker.caretaker_id in ^uids(caretaker) or
        circle.id in ^e(opts, :extra_ids_to_include, [])
    )
  end

  def query_my(:instance, opts),
    do: Bonfire.Boundaries.Scaffold.Instance.admin_circle() |> query_my(opts)

  @doc """
  Generates a query for a specific circle owned by a user.

  ## Examples

      iex> Bonfire.Boundaries.Circles.query_my_by_id("circle_id", user)
  """
  def query_my_by_id(id, caretaker, opts \\ []) do
    query_my(caretaker, opts)
    # |> reusable_join(:inner, [circle: circle], caretaker in assoc(circle, :caretaker), as: :caretaker)
    |> query_by_id(
      id,
      opts
    )
  end

  def exists?(id, opts \\ []) do
    query(opts)
    # |> reusable_join(:inner, [circle: circle], caretaker in assoc(circle, :caretaker), as: :caretaker)
    |> query_by_id(
      id,
      opts
    )
    |> repo().exists?()
  end

  defp query_by_id(query, id, _opts \\ []) do
    query
    |> where(
      [circle: circle],
      circle.id == ^uid!(id)
    )
  end

  @doc """
  Retrieves or creates a circle by name for a caretaker.

  ## Examples

      iex> Bonfire.Boundaries.Circles.get_or_create("New Circle", user)
      {:ok, %Circle{id: "new_circle_id", name: "New Circle"}}
  """
  def get_or_create(name, caretaker \\ nil) when is_binary(name) do
    # instance-wide circle if not user provided
    caretaker = caretaker || Bonfire.Boundaries.Scaffold.Instance.admin_circle()

    case get_by_name(name, caretaker) do
      {:ok, circle} ->
        {:ok, circle}

      _none ->
        debug(name, "circle unknown, create it now")
        create(caretaker, name)
    end
  end

  @doc """
  Edits a circle's attributes.

  ## Examples

      iex> Bonfire.Boundaries.Circles.edit(circle, user, %{name: "Updated Circle"})
      {:ok, %Circle{id: "circle_id", name: "Updated Circle"}}
  """
  def edit(%Circle{} = circle, %User{} = _user, params) do
    circle = repo().maybe_preload(circle, [:encircles, :named, :extra_info])

    params
    |> input_to_atoms()
    |> Changesets.put_id_on_mixins([:named, :extra_info], circle)
    # |> input_to_atoms()
    # |> Map.update(:named, nil, &Map.put(&1, :id, uid(circle)))
    # |> Map.update(:extra_info, nil, &Map.put(&1, :id, uid(circle)))
    |> changeset(:update, circle, ...)
    |> repo().update()
  end

  def edit(id, %User{} = user, params) do
    with {:ok, circle} <- get_for_caretaker(id, user) do
      edit(circle, user, params)
    end
  end

  @doc """
  Adds subject(s) to circle(s).

  ## Examples

      iex> Bonfire.Boundaries.Circles.add_to_circles(user, circle)
      {:ok, %Encircle{}}

      iex> Bonfire.Boundaries.Circles.add_to_circles([user1, user2], [circle1, circle2])
      [{{:ok, %Encircle{}}, {:ok, %Encircle{}}}, {{:ok, %Encircle{}}, {:ok, %Encircle{}}}]
  """
  def add_to_circles(_subject, circles)
      when is_nil(circles) or (is_list(circles) and length(circles) == 0),
      do: error(circles, "No circle provided to add to")

  def add_to_circles(subjects, _circles)
      when is_nil(subjects) or (is_list(subjects) and length(subjects) == 0),
      do: error(subjects, "No subject provided to add to a circle")

  def add_to_circles(subjects, circle) when is_list(subjects) do
    # TODO: optimise
    Enum.map(subjects, &add_to_circles(&1, circle))
  end

  def add_to_circles(subject, circles) when is_list(circles) do
    # TODO: optimise
    Enum.map(circles, &add_to_circles(subject, &1))
  end

  def add_to_circles(subject, circle) when not is_nil(circle) do
    repo().insert(Encircle.changeset(%{circle_id: uid!(circle), subject_id: uid!(subject)}))
  end

  @doc """
  Removes a user from circles.

  ## Examples

      iex> Bonfire.Boundaries.Circles.remove_from_circles(user, circle)
      {1, nil}

      iex> Bonfire.Boundaries.Circles.remove_from_circles(user, [circle1, circle2])
      {2, nil}
  """
  def remove_from_circles(_subject, circles)
      when is_nil(circles) or circles == [],
      do: error("No circle provided, so could not remove")

  def remove_from_circles(subject, _circles)
      when is_nil(subject) or subject == [],
      do: error("No subject provided, so could not remove")

  def remove_from_circles(subject, circles) do
    from(e in Encircle,
      where: e.subject_id in ^Types.uids(subject) and e.circle_id in ^Types.uids(circles)
    )
    |> repo().delete_all()
  end

  @doc """
  Empties circles by removing all members.

  ## Examples

      iex> Bonfire.Boundaries.Circles.empty_circles([circle1, circle2])
      {10, nil}
  """
  def empty_circles(circles) do
    from(e in Encircle,
      where: e.circle_id in ^uids(circles)
    )
    |> repo().delete_all()
  end

  @doc """
  Removes user(s) from all circles.

  ## Examples

      iex> Bonfire.Boundaries.Circles.empty_circles([circle1, circle2])
      {10, nil}
  """
  def leave_all_circles(users) do
    from(e in Encircle,
      where: e.subject_id in ^uids(users)
    )
    |> repo().delete_all()
  end

  @doc """
  Deletes a circle and its associated data, including membership and boundary information. This will affect all objects previously shared with members of this circle

  ## Examples

      iex> Bonfire.Boundaries.Circles.delete(circle, [current_user: user])

      iex> Bonfire.Boundaries.Circles.delete("circle_id", [current_user: user])
  """
  def delete(%Circle{} = circle, opts) do
    Bonfire.Common.Utils.maybe_apply(
      Bonfire.Social.Objects,
      :maybe_generic_delete,
      [
        Circle,
        circle,
        [
          current_user: current_user(opts),
          delete_associations: [:encircles, :caretaker, :named, :extra_info, :stereotyped]
        ]
      ]
    )
  end

  def delete(id, opts) do
    with {:ok, circle} <- get_for_caretaker(id, current_user(opts)) do
      delete(circle, opts)
    end
  end
end
