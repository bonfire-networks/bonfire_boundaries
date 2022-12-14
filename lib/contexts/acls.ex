defmodule Bonfire.Boundaries.Acls do
  @moduledoc """
  acls represent fully populated access control rules that can be reused
  """
  use Arrows
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  import Ecto.Query
  import EctoSparkles
  import Bonfire.Boundaries.Integration
  import Bonfire.Boundaries.Queries

  alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.Identity.ExtraInfo
  alias Bonfire.Data.Identity.Caretaker
  alias Bonfire.Boundaries.Stereotyped
  alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.AccessControl.Controlled
  alias Bonfire.Data.AccessControl.Grant

  alias Bonfire.Data.Identity.User
  alias Bonfire.Boundaries
  # alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Verbs
  alias Ecto.Changeset
  alias Pointers.Changesets
  alias Pointers.ULID

  # don't show "others who silenced me"
  @exclude_stereotypes ["2HEYS11ENCEDMES0CAN0TSEEME"]

  # special built-in acls (eg, guest, local, activity_pub)
  def acls, do: Config.get(:acls)

  def preset_acl_ids do
    filter_acls =
      Config.get(:public_acls_on_objects, [
        :guests_may_see_read,
        :locals_may_interact,
        :locals_may_reply
      ])
      |> Enum.map(&get_id!/1)
  end

  def get(slug) when is_atom(slug), do: acls()[slug]

  def get!(slug) when is_atom(slug) do
    # || ( Bonfire.Boundaries.Fixtures.insert && get(slug) )
    get(slug) ||
      raise RuntimeError, message: "Missing default acl: #{inspect(slug)}"
  end

  def get_id(slug), do: e(acls(), slug, :id, nil)
  def get_id!(slug), do: get!(slug)[:id]

  def cast(changeset, creator, opts) do
    opts
    |> info("opts")

    to_boundaries =
      Boundaries.boundaries_set(maybe_from_opts(opts, :boundary, opts))
      |> info("to_boundaries")

    preset =
      Boundaries.preset_name(to_boundaries)
      |> info("preset_name")

    # id = Changeset.get_field(changeset, :id)
    # add ACLs based on any boundary presets (eg. public/local/mentions)
    # add any ACLs directly specified in input
    acls =
      base_acls(creator, preset, opts) ++
        maybe_add_direct_acl_ids(to_boundaries)

    debug(acls, "preset + inputted ACLs to set")

    case custom_recipients(changeset, preset, opts) do
      [] ->
        Changesets.put_assoc(changeset, :controlled, acls)

      custom_recipients ->
        acl_id = ULID.generate()
        controlled = [%{acl_id: acl_id} | acls]

        custom_grants =
          (e(opts, :verbs_to_grant, nil) ||
             Config.get!([:verbs_to_grant, :default]))
          |> debug("verbs_to_grant")
          |> Enum.flat_map(custom_recipients, &grant_to(&1, acl_id, ...))

        # |> debug("on-the-fly ACLs to create")

        changeset
        |> Changeset.prepare_changes(fn changeset ->
          changeset.repo.insert!(%Acl{id: acl_id})
          changeset.repo.insert_all(Grant, custom_grants)
          changeset
        end)
        |> Changesets.put_assoc!(:controlled, controlled)
    end
  end

  # when the user picks a preset, this maps to a set of base acls
  defp base_acls(user, preset, _opts) do
    (Config.get!([:object_default_boundaries, :acls]) ++
       Boundaries.acls_from_preset_boundary_names(preset))
    |> info("preset ACLs to set (based on preset #{preset}) ")
    |> find_acls(user)
  end

  defp maybe_add_direct_acl_ids(acls) when is_list(acls) do
    ulids(acls)
    |> filter_empty([])
    |> Enum.map(&maybe_add_direct_acl_id/1)
  end

  defp maybe_add_direct_acl_id(id) when is_binary(id) do
    %{acl_id: id}
  end

  defp custom_recipients(changeset, preset, opts) do
    (reply_to_grants(changeset, preset, opts) ++
       mentions_grants(changeset, preset, opts) ++
       maybe_custom_circles_or_users(opts))
    |> Enum.uniq()
    |> filter_empty([])
  end

  defp maybe_custom_circles_or_users(opts),
    do: maybe_from_opts(opts, :to_circles, [])

  defp reply_to_grants(changeset, preset, _opts) do
    reply_to_creator =
      Utils.e(
        changeset,
        :changes,
        :replied,
        :changes,
        :replying_to,
        :created,
        :creator,
        nil
      )

    if reply_to_creator do
      # debug(reply_to_creator, "creators of reply_to should be added to a new ACL")

      case preset do
        "public" ->
          [ulid(reply_to_creator)]

        "local" ->
          if is_local?(reply_to_creator),
            do: [ulid(reply_to_creator)],
            else: []

        _ ->
          []
      end
    else
      []
    end
  end

  defp mentions_grants(changeset, preset, _opts) do
    mentions = Utils.e(changeset, :changes, :post_content, :changes, :mentions, nil)

    if mentions && mentions != [] do
      # debug(mentions, "mentions/tags may be added to a new ACL")

      case preset do
        "public" ->
          ulid(mentions)

        "mentions" ->
          ulid(mentions)

        "local" ->
          # include only if local
          mentions
          |> Enum.filter(&is_local?/1)
          |> ulid()

        _ ->
          # do not grant to mentions by default
          []
      end
    else
      []
    end
  end

  defp find_acls(acls, user)
       when is_list(acls) and length(acls) > 0 and
              (is_binary(user) or is_map(user)) do
    acls =
      acls
      |> Enum.map(&identify/1)
      # |> info("identified")
      |> filter_empty([])
      |> Enum.group_by(&elem(&1, 0))

    globals =
      acls
      |> Map.get(:global, [])
      |> Enum.map(&elem(&1, 1))

    # |> info("globals")
    stereo =
      case Map.get(acls, :stereo, []) do
        [] ->
          []

        stereo ->
          stereo
          |> Enum.map(&elem(&1, 1).id)
          |> find_caretaker_stereotypes(user, ...)

          # |> info("stereos")
      end

    Enum.map(globals ++ stereo, &%{acl_id: &1.id})
  end

  defp find_acls(_acls, _) do
    warn("You need to provide an object creator to properly set ACLs")
    []
  end

  defp identify(name) do
    case user_default_acl(name) do
      # seems to be a global ACL
      nil ->
        {:global, get!(name)}

      # should be a user-level stereotyped ACL
      default ->
        case default[:stereotype] do
          nil ->
            raise RuntimeError,
              message: "Boundaries: Unstereotyped user acl in config: #{inspect(name)}"

          stereo ->
            {:stereo, get!(stereo)}
        end
    end
  end

  defp grant_to({subject_id, role}, acl_id, default_verbs) do
    role_verbs = Bonfire.Boundaries.role_verbs()
    roles = role_verbs |> Keyword.keys()

    role =
      role
      |> maybe_to_atom()
      |> debug

    if is_atom(role) and not is_nil(role) and role in roles do
      grant_to(subject_id, acl_id, role_verbs[role])
    else
      case ulid(subject_id) do
        nil -> nil
        id -> grant_to(id, acl_id, default_verbs)
      end
    end
  end

  defp grant_to(user_etc, acl_id, verbs) when is_list(verbs),
    do: Enum.map(verbs, &grant_to(user_etc, acl_id, &1))

  defp grant_to(user_etc, acl_id, verb) do
    debug(user_etc)

    %{
      id: ULID.generate(),
      acl_id: acl_id,
      subject_id: user_etc,
      verb_id: Verbs.get_id!(verb),
      value: true
    }
  end

  ## invariants:

  ## * All a user's ACLs will have the user as an administrator but it
  ##   will be hidden from the user

  def create(attrs \\ %{}, opts) do
    attrs
    |> input_to_atoms()
    |> changeset(:create, ..., opts)
    |> repo().insert()
  end

  def changeset(:create, attrs, opts) do
    changeset(:create, attrs, opts, Keyword.fetch!(opts, :current_user))
  end

  defp changeset(:create, attrs, _opts, :system), do: changeset_cast(attrs)

  defp changeset(:create, attrs, opts, :instance),
    do:
      changeset(:create, attrs, opts, %{
        id: Bonfire.Boundaries.Fixtures.admin_circle()
      })

  defp changeset(:create, attrs, _opts, %{id: id}) do
    Changesets.cast(%Acl{}, %{caretaker: %{caretaker_id: id}}, [])
    |> changeset_cast(attrs)
  end

  defp changeset_cast(acl \\ %Acl{}, attrs) do
    Acl.changeset(acl, attrs)
    # |> IO.inspect(label: "cs")
    |> Changesets.cast_assoc(:named, with: &Named.changeset/2)
    |> Changesets.cast_assoc(:extra_info, with: &ExtraInfo.changeset/2)
    |> Changesets.cast_assoc(:caretaker, with: &Caretaker.changeset/2)
    |> Changesets.cast_assoc(:stereotyped)
  end

  def get_for_caretaker(id, caretaker, opts \\ []) do
    with {:ok, acl} <- repo().single(get_for_caretaker_q(id, caretaker, opts)) do
      {:ok, acl}
    else
      {:error, :not_found} ->
        if is_admin?(caretaker),
          do:
            repo().single(
              get_for_caretaker_q(
                id,
                Bonfire.Boundaries.Fixtures.admin_circle(),
                opts
              )
            ),
          else: {:error, :not_found}
    end
  end

  def get_for_caretaker_q(id, caretaker, opts \\ []) do
    list_q(opts ++ [skip_boundary_check: true])
    # |> reusable_join(:inner, [circle: circle], caretaker in assoc(circle, :caretaker), as: :caretaker)
    |> maybe_for_caretaker(id, caretaker)
  end

  defp maybe_for_caretaker(query, id, caretaker) do
    if id in built_in_ids() do
      where(query, [acl], acl.id == ^ulid!(id))
    else
      # |> reusable_join(:inner, [circle: circle], caretaker in assoc(circle, :caretaker), as: :caretaker)
      where(
        query,
        [acl, caretaker: caretaker],
        acl.id == ^ulid!(id) and caretaker.caretaker_id == ^ulid!(caretaker)
      )
    end
  end

  @doc """
  Lists ACLs we are permitted to see.
  """
  def list(opts \\ []) do
    list_q(opts)
    |> repo().many()
  end

  def list_q(opts \\ []) do
    from(acl in Acl, as: :acl)
    |> boundarise(acl.id, opts)
    |> proload([
      :caretaker,
      :named,
      :extra_info,
      stereotyped: {"stereotype_", [:named]}
    ])
    |> maybe_search(opts[:search])
  end

  def maybe_search(query, text) when is_binary(text) and text != "" do
    query
    |> where(
      [named: named, stereotype_named: stereotype_named],
      ilike(named.name, ^"#{text}%") or
        ilike(named.name, ^"% #{text}%") or
        ilike(stereotype_named.name, ^"#{text}%") or
        ilike(stereotype_named.name, ^"% #{text}%")
    )
  end

  def maybe_search(query, _), do: query

  # def list_all do
  #   from(u in Acl, as: :acl)
  #   |> proload([:named, :controlled, :stereotyped, :caretaker])
  #   |> repo().many()
  # end

  def built_in_ids do
    acls()
    |> Map.values()
    |> Enum.map(& &1.id)
  end

  def stereotype_ids do
    acls()
    |> Map.values()
    |> Enum.filter(&e(&1, :stereotype, nil))
    |> Enum.map(& &1.id)
  end

  def is_stereotype?(%{stereotyped: %{stereotype_id: stereotype_id}} = _acl)
      when is_binary(stereotype_id) do
    true
  end

  def is_stereotype?(acl) do
    # debug(acl)
    ulid(acl) in stereotype_ids()
  end

  def list_built_ins do
    list_q(skip_boundary_check: true)
    |> where([acl], acl.id in ^built_in_ids)
    |> repo().many()
  end

  # TODO
  defp built_ins_for_dropdown do
    filter = Config.get(:acls_to_present)

    acls()
    |> Enum.filter(fn {name, acl} -> name in filter end)
    |> Enum.map(fn {name, acl} -> acl.id end)
  end

  def opts_for_dropdown() do
    built_ins = built_ins_for_dropdown()

    [
      extra_ids_to_include: built_ins,
      exclude_ids:
        @exclude_stereotypes ++
          [
            "71MAYADM1N1STERMY0WNSTVFFS",
            "0H0STEDCANTSEE0RD0ANYTH1NG",
            "1S11ENCEDTHEMS0CAN0TP1NGME"
          ]
    ]
  end

  def for_dropdown(opts) do
    list_my_with_counts(current_user(opts), opts ++ opts_for_dropdown())
  end

  @doc """
  Lists the ACLs we are the registered caretakers of that we are
  permitted to see. If any are created without permitting the
  user to see them, they will not be shown.
  """
  def list_my(user, opts \\ []), do: repo().many(list_my_q(user, opts))

  def list_my_with_counts(user, opts \\ []) do
    list_my_q(user, opts)
    |> join(
      :left,
      [acl],
      grants in subquery(
        from(g in Grant,
          group_by: g.acl_id,
          select: %{acl_id: g.acl_id, count: count()}
        )
      ),
      on: grants.acl_id == acl.id,
      as: :grants
    )
    |> join(
      :left,
      [acl],
      controlled in subquery(
        from(c in Controlled,
          group_by: c.acl_id,
          select: %{acl_id: c.acl_id, count: count()}
        )
      ),
      on: controlled.acl_id == acl.id,
      as: :controlled
    )
    |> select_merge([grants: grants, controlled: controlled], %{
      grants_count: grants.count,
      controlled_count: controlled.count
    })
    |> order_by([grants: grants, controlled: controlled],
      desc_nulls_last: controlled.count,
      desc_nulls_last: grants.count
    )
    |> repo().many()
  end

  @doc "query for `list_my`"
  def list_my_q(user, opts \\ []) do
    list_q(skip_boundary_check: true)
    |> where(
      [acl, caretaker: caretaker],
      caretaker.caretaker_id == ^ulid!(user) or
        (acl.id in ^e(opts, :extra_ids_to_include, []) and
           acl.id not in ^e(opts, :exclude_ids, @exclude_stereotypes))
    )
    |> where(
      [stereotyped: stereotyped],
      is_nil(stereotyped.id) or
        stereotyped.stereotype_id not in ^e(
          opts,
          :exclude_ids,
          @exclude_stereotypes
        )
    )
  end

  def user_default_acl(name), do: user_default_acls()[name]

  # FIXME: this vs acls/0 ?
  def user_default_acls() do
    Map.fetch!(Boundaries.user_default_boundaries(), :acls)

    # |> debug
  end

  def find_caretaker_stereotypes(caretaker, stereotypes) do
    from(a in Acl,
      join: c in Caretaker,
      on: a.id == c.id and c.caretaker_id == ^ulid(caretaker),
      join: s in Stereotyped,
      on: a.id == s.id and s.stereotype_id in ^stereotypes,
      preload: [caretaker: c, stereotyped: s]
    )
    |> repo().all()

    # |> debug("stereotype acls")
  end

  def edit(%Acl{} = acl, %User{} = user, params) do
    acl = repo().maybe_preload(acl, [:named, :extra_info])

    params
    |> input_to_atoms()
    |> Changesets.put_id_on_mixins([:named, :extra_info], acl)
    |> changeset_cast(acl, ...)
    |> repo().update()
  end

  def edit(id, %User{} = user, params) do
    with {:ok, acl} <- get_for_caretaker(id, user) do
      edit(acl, user, params)
    end
  end

  @doc """
  Fully delete the ACL, including permissions/grants and controlled information. This will affect all objects previously shared with this ACL.
  """
  def delete(%Acl{} = acl, opts) do
    assocs = [
      :grants,
      :controlled,
      :caretaker,
      :named,
      :extra_info,
      :stereotyped
    ]

    Bonfire.Social.Objects.maybe_generic_delete(Acl, acl,
      current_user: current_user(opts),
      delete_associations: assocs
    )
  end

  def delete(id, opts) do
    with {:ok, acl} <- get_for_caretaker(id, current_user(opts)) do
      delete(acl, opts)
    end
  end

  @doc """
  Soft-delete the ACL, meaning it will not be displayed anymore, but permissions/grants and controlled information will be preserved. This will not affect objects previously shared with this ACL.
  """
  def soft_delete(%Acl{} = acl, _opts) do
    # FIXME
    Bonfire.Common.Repo.Delete.soft_delete(acl)

    # acl |> repo().delete()
  end

  def soft_delete(id, opts) do
    with {:ok, acl} <- get_for_caretaker(id, current_user(opts)) do
      soft_delete(acl, opts)
    end
  end
end
