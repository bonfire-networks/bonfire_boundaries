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
  Lists all built-in circles. Returns Circle structs.

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

  @doc """
  Checks if a circle is a built-in circle.
  """
  def is_built_in?(circle, built_in_ids \\ built_in_ids()) do
    # debug(acl)
    uid(circle) in built_in_ids
  end

  @doc """
  Checks if a circle is a stereotype circle.

  ## Examples

      iex> Bonfire.Boundaries.Circles.is_stereotype?("7DAPE0P1E1PERM1TT0F0110WME")
      true

      iex> Bonfire.Boundaries.Circles.is_stereotype?("custom_circle_id")
      false
  """
  def is_stereotype?(circle, stereotype_ids \\ stereotype_ids()) do
    uid(circle) in stereotype_ids
  end

  @doc """
  Retrieves a circle by its slug or ID.

  ## Examples

      iex> Bonfire.Boundaries.Circles.get_built_in(:guest)
      %{id: "guest_circle_id", name: "Guest"}

      iex> Bonfire.Boundaries.Circles.get_built_in("circle_id")
      %{id: "circle_id", name: "Custom Circle"}
  """
  def get_built_in(id_or_slug, all_circles \\ circles())
  def get_built_in(slug, all_circles) when is_atom(slug), do: (all_circles || circles())[slug]

  def get_built_in(id, all_circles) when is_binary(id),
    do: get_tuple(id, all_circles) |> Enums.maybe_elem(1)

  def get_built_in!(slug) when is_atom(slug) do
    get_built_in(slug) ||
      raise RuntimeError, message: "Missing built-in circle: #{inspect(slug)}"
  end

  @doc "Gets a circle by ID, after checking boundaries to see if this is a list shared with me"
  def get(id, opts) do
    opts = opts ++ @default_q_opts
    caretaker = current_user(opts)

    with {:ok, circle} <-
           query(opts)
           |> query_by_id(id, opts)
           #  |> boundarise(circle.id, opts)
           |> where(
             [circle, caretaker: caretaker],
             exists(boundarise(circle.id, opts)) or
               caretaker.caretaker_id in ^uids(caretaker) or
               circle.id in ^e(opts, :extra_ids_to_include, [])
           )
           |> repo().single() do
      {:ok, circle}
    end
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

  def get_id!(slug) when is_atom(slug), do: get_built_in!(slug).id

  @doc """
  Retrieves a tuple containing the name and ID of a circle by its slug or ID.

  ## Examples

      iex> Bonfire.Boundaries.Circles.get_tuple(:guest)
      {"Guest", "guest_circle_id"}

      iex> Bonfire.Boundaries.Circles.get_tuple("circle_id")
      {:my_circle, %{id: "circle_id", name: "My Circle"}}
  """
  def get_tuple(id, all_circles \\ circles())

  def get_tuple(slug, _all_circles) when is_atom(slug) do
    {Config.get!([:circles, slug, :name]), Config.get!([:circles, slug, :id])}
  end

  def get_tuple(id, all_circles) when is_binary(id) do
    Enum.find(all_circles || circles(), fn {_slug, c} ->
      c[:id] == id
    end)
  end

  @doc """
  Retrieves a circle slug by its ID or name.

    ## Examples

      iex> get_slug("guest_circle_id")
      :guest
  """
  def get_slug(id_or_name, all_circles \\ circles()) do
    case get_tuple(id_or_name, all_circles) do
      {slug, _verb} -> slug
      _ -> nil
    end
  end

  def get_slugs(circles, all_circles \\ circles()) do
    circles
    |> Enum.map(fn
      %{stereotyped: %{stereotype_id: stereotype_id}} ->
        Circles.get_slug(stereotype_id, all_circles)

      %{id: id} ->
        Circles.get_slug(id, all_circles)
    end)
  end

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
  Lists default circles for a user.

  ## Examples

      iex> Bonfire.Boundaries.Circles.list_my_defaults()
      [{"Guest", "guest_circle_id"}, {"Local", "local_circle_id"}, {"ActivityPub", "activity_pub_circle_id"}]
  """
  def list_my_defaults(_user \\ nil) do
    # TODO make configurable
    Enum.map([:guest, :local, :activity_pub], &Circles.get_tuple/1)
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

  # def preload_encircled_by(subject, circles, opts \\ []) do
  #   circles
  #   |> repo().preload([encircles: encircled_by_q(subject)], opts)
  # end

  # Add this function to your Circles module

  @doc """
  Determines if a user is in specific circles.
  Returns the original circles list with a boolean field added to each circle.
  """
  def list_subject_in_circles(subject_id, circles, opts \\ []) when is_list(circles) do
    subject_ids = Types.uids(subject_id)

    if Enum.empty?(subject_ids) or Enum.empty?(circles) do
      circles
    else
      field = opts[:boolean_field] || :encircle_subjects
      reload_circle_id = opts[:reload_circle_id]
      # Can be :increment, :decrement, or nil
      inc_reload_count = opts[:inc_reload_count]

      # Single split_with that determines which circles need checking
      {circles_to_check, other_circles} =
        Enum.split_with(circles, fn %{id: id} = circle ->
          # Check if this is the circle to reload OR if it doesn't have the field set yet
          id == reload_circle_id || not is_boolean(Map.get(circle, field))
        end)

      if Enum.empty?(circles_to_check) do
        # No circles need membership status checked
        circles
      else
        # Get all membership pairs in a single query
        memberships =
          from(e in Encircle,
            where: e.subject_id in ^subject_ids and e.circle_id in ^Types.uids(circles_to_check),
            select: e.circle_id
          )
          |> repo().all()
          |> MapSet.new()

        # Annotate circles with membership status
        updated_circles =
          Enum.map(circles_to_check, fn %{id: id} = circle ->
            # Add the membership boolean flag
            circle = Map.put(circle, field, MapSet.member?(memberships, id))

            # Update count only if requested and this is the specific circle being reloaded
            if id == reload_circle_id && inc_reload_count &&
                 Map.has_key?(circle, :encircles_count) do
              # Update the count, ensuring it never goes below zero
              Map.put(
                circle,
                :encircles_count,
                max(0, (circle.encircles_count || 0) + inc_reload_count)
              )
            else
              circle
            end
          end)

        # Combine updated circles with other circles that weren't checked
        updated_circles ++ other_circles
      end
    end
  end

  ## invariants:
  ## * Created circles will have the user as a caretaker

  @doc """
  Returns a list of built-in and stereotyped circle structs for the user.

  ## Options

    * `:include_circles` - restrict which built-in circles to include (list of atoms, defaults to all)

  ## Examples

      iex> list_user_built_ins(user)
      [%Circle{id: "0AND0MSTRANGERS0FF1NTERNET", name: l("Guests")}, ...]

      iex> list_user_built_ins(user, include_circles: [:followers, :public])
      [%Circle{id: "0AND0MSTRANGERS0FF1NTERNET", name: l("Guests")}, %Circle{id: "XYZ", name: l("Followers")}, ...]

  """
  def list_user_built_ins(user, opts \\ []) do
    all_circles = circles()

    # 1. Built-in circles, optionally filtered by opts[:include_circles]
    built_in_circles =
      case opts[:include_circles] do
        nil ->
          # TODO: optionally also include user's public circles?
          list_built_ins()

        slugs when is_list(slugs) ->
          slugs
          |> Enum.map(&get_built_in(&1, all_circles))
          |> Enum.filter(& &1)
      end

    stereotype_ids = stereotype_ids()

    {stereotyped, built_in_circles} =
      Enum.split_with(built_in_circles, &is_stereotype?(&1, stereotype_ids))

    # 2. Stereotype circles for the user 
    stereotype_structs = get_stereotype_circles(user, stereotyped)

    # 3. Combine and return
    built_in_circles ++ stereotype_structs
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
    stereotype_ids = stereotype_ids(stereotypes)

    if is_list(subject) do
      Enum.flat_map(subject, &do_get_stereotype_circles(&1, stereotype_ids))
    else
      do_get_stereotype_circles(subject, stereotype_ids)
    end
  end

  def get_stereotype_circles(subject, stereotype)
      when not is_nil(stereotype) and stereotype != [],
      do: get_stereotype_circles(subject, [stereotype])

  defp do_get_stereotype_circles(subject, stereotype_ids)
       when is_list(stereotype_ids) and stereotype_ids != [] do
    # skip boundaries since we should only use this query internally
    query_my(subject, skip_boundary_check: true)
    |> where(
      [circle: circle, stereotyped: stereotyped],
      stereotyped.stereotype_id in ^stereotype_ids
    )
    |> repo().all()
  end

  defp do_get_stereotype_circles(_subject, _stereotype_ids) do
    []
  end

  def stereotype_ids(stereotypes),
    do:
      Enum.map(stereotypes, fn
        %{id: id} when is_binary(id) -> id
        stereo -> Bonfire.Boundaries.Circles.get_id!(stereo)
      end)
      |> Enums.ids()

  @doc """
  Fast lookup of user's stereotype circle IDs (for block checking).

  Unlike `get_stereotype_circles/2`, this function returns only circle IDs without loading full circle structs or associations. Use this when you only need IDs for membership checks.

  ## Examples

      iex> Bonfire.Boundaries.Circles.get_stereotype_circle_ids(user, [:ghost_them, :silence_them])
      ["circle_id_1", "circle_id_2"]
  """
  def get_stereotype_circle_ids(subjects, stereotypes)
      when is_list(stereotypes) and stereotypes != [] do
    stereotype_ids = stereotype_ids(stereotypes)

    caretaker_ids = Enums.ids(subjects)

    if is_list(caretaker_ids) and caretaker_ids != [] and is_list(stereotype_ids) and
         stereotype_ids != [] do
      from(c in Circle,
        join: ct in assoc(c, :caretaker),
        join: st in assoc(c, :stereotyped),
        where: ct.caretaker_id in ^caretaker_ids,
        where: st.stereotype_id in ^stereotype_ids,
        select: c.id
      )
      |> repo().all()
    else
      []
    end
  end

  def get_stereotype_circle_ids(subject, stereotype)
      when not is_nil(stereotype) and stereotype != [],
      do: get_stereotype_circle_ids(subject, [stereotype])

  def get_stereotype_circle_ids(_subject, _stereotypes), do: []

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
  def list_my(user, opts \\ []) do
    all_circles = circles()

    repo().many(query_my(user, opts ++ @default_q_opts))
    |> Enum.map(fn
      %{stereotyped: %{stereotype_id: stereotype_id} = stereotyped} = circle
      when not is_nil(stereotype_id) ->
        config =
          get_built_in(stereotype_id, all_circles)
          |> debug("config for stereotype #{stereotype_id}")

        # Merge name and icon from config 
        if is_map(config) or Keyword.keyword?(config) do
          circle
          |> Map.put(
            :stereotyped,
            stereotyped
            |> update_meta_from_config(config[:icon], config[:name])
          )
        else
          circle
        end

      %{id: id} = circle ->
        config =
          get_built_in(id, all_circles)
          |> debug("config for #{id}")

        # Merge name and icon from config 
        if is_map(config) or Keyword.keyword?(config) do
          circle
          |> update_meta_from_config(config[:icon], config[:name])
        else
          circle
        end

      circle ->
        circle
    end)
    |> debug("updated_circles_list")
  end

  defp update_meta_from_config(object, icon, name) do
    named = %{name: name}
    extra_info = %{icon: icon}

    object
    |> Map.update(:named, named, fn val -> if(name, do: named, else: val) end)
    |> Map.update(:extra_info, extra_info, fn
      %{} = val -> if(icon, do: Map.merge(val, extra_info), else: val)
      val -> if(icon, do: extra_info, else: val)
    end)
  end

  @doc """
  Fast query for sidebar - uses indexed lookup on caretaker_id first.
  Only preloads :named and :stereotyped (what sidebar actually uses).

  ## Examples

      iex> Bonfire.Boundaries.Circles.list_my_for_sidebar(user, exclude_stereotypes: true)
      [%Circle{id: "circle_id1", named: %{name: "My Circle"}}]
  """
  def list_my_for_sidebar(user, opts \\ []) do
    user_id = uid!(user)

    exclude_circles =
      e(opts, :exclude_circles, []) ++
        if opts[:exclude_built_ins],
          do: built_in_ids(),
          else:
            if(opts[:exclude_stereotypes],
              do: stereotype_ids(),
              else: []
            )

    # Step 1: Get circle IDs for this user (fast - uses caretaker_id index)
    circle_ids =
      from(c in Caretaker,
        where: c.caretaker_id == ^user_id,
        select: c.id
      )
      |> repo().all()
      |> Enum.reject(&(&1 in exclude_circles))

    # Step 2: Fetch those specific circles with minimal preloads
    from(circle in Circle, as: :circle)
    |> where([circle], circle.id in ^circle_ids)
    |> proload([
      :named,
      stereotyped: {"stereotype_", [:named]}
    ])
    |> where(
      [stereotyped: stereotyped],
      is_nil(stereotyped.id) or stereotyped.stereotype_id not in ^exclude_circles
    )
    |> repo().all()
    |> merge_stereotype_config()
  end

  defp merge_stereotype_config(circles) do
    all_circles = circles()

    Enum.map(circles, fn
      %{stereotyped: %{stereotype_id: stereotype_id} = stereotyped} = circle
      when not is_nil(stereotype_id) ->
        config = get_built_in(stereotype_id, all_circles)

        if is_map(config) or Keyword.keyword?(config) do
          Map.put(circle, :stereotyped, update_meta_from_config(stereotyped, config[:icon], config[:name]))
        else
          circle
        end

      %{id: id} = circle ->
        config = get_built_in(id, all_circles)

        if is_map(config) or Keyword.keyword?(config) do
          update_meta_from_config(circle, config[:icon], config[:name])
        else
          circle
        end

      circle ->
        circle
    end)
  end

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
                  do: stereotypes(:block),
                  else: []
                )
            )
            |> debug("excluding circles")

    from(circle in Circle, as: :circle)
    |> proload([
      :named,
      :extra_info,
      :caretaker,
      # :stereotyped
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
      [named: named, stereotype_named: stereotype_named],
      named.name == ^text or
        stereotype_named.name == ^text
    )
  end

  defp maybe_by_name(query, _), do: query

  defp maybe_by_name_basic(query, text) when is_binary(text) and text != "" do
    query
    |> where(
      [named: named],
      named.name == ^text
    )
  end

  defp maybe_by_name_basic(query, _), do: query

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
    |> maybe_by_name_basic(opts[:name])
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
  Lists members of a circle with cursor-based pagination using Paginator.

  ## Options
    * `:cursor` - The cursor for pagination (optional)
    * `:limit` - The maximum number of members to return (default: 12)
    * `:preload` - Associations to preload (optional)

  ## Examples
      iex> Bonfire.Boundaries.Circles.list_members("circle_id", limit: 10)
      %Paginator.Page{entries: [%Encircle{}, ...], metadata: %{...}}
  """
  def list_members(circle, opts \\ []) do
    query =
      from e in Encircle,
        where: e.circle_id == ^Types.uid!(circle)

    # Order by insertion time for consistent cursor pagination
    query =
      query
      |> proload(subject: [:character, :profile, :named])

    # Use Paginator for cursor-based pagination
    many(
      query,
      Keyword.get(opts, :paginate, true),
      opts
    )
  end

  @doc """
  Counts the total number of members in a circle.
  """
  def count_members(circle) do
    query =
      from e in Encircle,
        where: e.circle_id == ^Types.uid!(circle),
        select: count(e.id)

    repo().one(query) || 0
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
    |> repo().delete_many()
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
    |> repo().delete_many()
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
    |> repo().delete_many()
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

  @doc """
  Returns the IDs of subjects that are members of any of the given circles.

  ## Examples

      iex> Bonfire.Boundaries.Circles.subject_ids_in_circles([user1, user2], [circle1, circle2])
      ["user1_id"]

  This is useful for efficiently filtering blocked users in batch.
  """
  def subject_ids_in_circles(subjects, circles) do
    subject_ids = Types.uids(subjects)
    circle_ids = Types.uids(circles)

    if Enum.empty?(subject_ids) or Enum.empty?(circle_ids) do
      []
    else
      from(e in Encircle,
        where: e.subject_id in ^subject_ids and e.circle_id in ^circle_ids,
        select: e.subject_id
      )
      |> repo().all()
      |> Enum.uniq()
    end
  end
end
