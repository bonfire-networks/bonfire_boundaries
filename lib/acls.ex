defmodule Bonfire.Boundaries.Acls do
  @moduledoc """
  Provides functionality for managing Access Control Lists (ACLs) in the Bonfire system.

  An `Acl` is a list of `Grant`s used to define access permissions for objects. It represents fully populated access control rules that can be reused. It can be used to secure multiple objects and exists independently of any object.

  > ACLs (also referred to as "preset boundaries") enable you to make a list of circles and users and then grant specific roles or permissions to each of those. For example, you might create a "Fitness" ACL and grant the "Participate" role to your gym buddies, allowing them to interact with your fitness-related content, while granting the "Interact" role to your family and friends, who can view and react to your posts but not comment on them.

  The corresponding Ecto schema is `Bonfire.Data.AccessControl.Acl` which is defined in a [seperate repo](https://github.com/bonfire-networks/bonfire_data_access_control).
  """
  use Arrows
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  import Ecto.Query
  import EctoSparkles
  import Bonfire.Boundaries.Integration
  # import Bonfire.Boundaries.Queries

  alias Bonfire.Data.Identity.Named
  alias Bonfire.Data.Identity.ExtraInfo
  alias Bonfire.Data.Identity.Caretaker
  alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.AccessControl.Controlled
  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.AccessControl.Stereotyped
  alias Needle.Pointer
  alias Bonfire.Data.Identity.User
  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.Controlleds
  alias Bonfire.Boundaries.Verbs
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Scaffold
  alias Bonfire.Boundaries.Grants
  alias Bonfire.Boundaries.Roles
  alias Ecto.Changeset
  alias Needle.Changesets
  alias Needle.ULID

  @doc """
  Returns a list of stereotype IDs to exclude from queries.

  ## Examples

      iex> Bonfire.Boundaries.Acls.exclude_stereotypes()
      ["2HEYS11ENCEDMES0CAN0TSEEME", "7HECVST0MAC1F0RAN0BJECTETC"]

      iex> Bonfire.Boundaries.Acls.exclude_stereotypes(false)
      ["2HEYS11ENCEDMES0CAN0TSEEME"]
  """
  def exclude_stereotypes(including_custom? \\ true)

  def exclude_stereotypes(false) do
    # don't show "others who silenced me"
    ["2HEYS11ENCEDMES0CAN0TSEEME"]
  end

  def exclude_stereotypes(_true) do
    # don't show "others who silenced me" and custom per-object ACLs
    ["2HEYS11ENCEDMES0CAN0TSEEME", "7HECVST0MAC1F0RAN0BJECTETC"]
  end

  @doc """
  Returns a list of default IDs to exclude from queries.

  ## Examples

      iex> Bonfire.Boundaries.Acls.default_exclude_ids()
      ["2HEYS11ENCEDMES0CAN0TSEEME", "7HECVST0MAC1F0RAN0BJECTETC", "71MAYADM1N1STERMY0WNSTVFFS", "0H0STEDCANTSEE0RD0ANYTH1NG", "1S11ENCEDTHEMS0CAN0TP1NGME"]
  """
  def default_exclude_ids(including_custom? \\ true) do
    exclude_stereotypes(including_custom?) ++
      [
        # admin
        "71MAYADM1N1STERMY0WNSTVFFS",
        #  ghosting
        "0H0STEDCANTSEE0RD0ANYTH1NG",
        # silencing
        "1S11ENCEDTHEMS0CAN0TP1NGME"
        # "1HANDP1CKEDZEPE0P1E1F0110W" # following
      ]
  end

  @doc """
  Returns a list of ACL IDs for remote public access.

  ## Examples

      iex> Bonfire.Boundaries.Acls.remote_public_acl_ids()
      ["5REM0TEPE0P1E1NTERACTREACT", "5REM0TEPE0P1E1NTERACTREP1Y", "7REM0TEACT0RSCANC0NTR1BVTE"]
  """
  def remote_public_acl_ids,
    do: ["5REM0TEPE0P1E1NTERACTREACT", "5REM0TEPE0P1E1NTERACTREP1Y", "7REM0TEACT0RSCANC0NTR1BVTE"]

  @doc """
  Returns a list of ACL IDs for a preset (eg. "local" and "public").
  """
  def preset_acl_ids(preset, preset_acls \\ Config.get!(:preset_acls_match)),
    do:
      (preset_acls[preset] || [])
      |> Enum.map(&get_id!/1)

  def preset_acl_ids do
    Config.get(:public_acls_on_objects, [
      :guests_may_see_read,
      :locals_may_interact,
      :locals_may_reply
    ])
    |> Enum.map(&get_id!/1)
  end

  @doc """
    Returns a list of special built-in ACLs (e.g., guest, local, activity_pub).
  """
  def acls, do: Config.get(:acls)

  @doc """
  Retrieves an ACL by its slug.

  ## Examples

      iex> Bonfire.Boundaries.Acls.get(:instance_care)

      iex> Bonfire.Boundaries.Acls.get(:non_existent)
      nil
  """
  def get(slug) when is_atom(slug), do: acls()[slug]

  @doc """
  Retrieves an ACL by its slug, raising an error if not found.
  """
  def get!(slug) when is_atom(slug) do
    # || ( Bonfire.Boundaries.Scaffold.insert && get(slug) )
    get(slug) ||
      raise RuntimeError, message: "Missing default acl: #{inspect(slug)}"
  end

  @doc """
  Retrieves an ACL ID by its slug.

  ## Examples

      iex> Bonfire.Boundaries.Acls.get_id(:instance_care)
      "01SETT1NGSF0R10CA11NSTANCE"

      iex> Bonfire.Boundaries.Acls.get_id(:non_existent)
      nil
  """
  def get_id(slug), do: e(acls(), slug, :id, nil)
  def get_id!(slug), do: get!(slug)[:id]

  def acl_id(:instance) do
    Bonfire.Boundaries.Scaffold.Instance.instance_acl()
  end

  def acl_id(obj) do
    uid(obj) || get_id!(obj)
  end

  @doc """
  Sets ACLs (existing ones or creating some on-the-fly) and Controlled on an object.

  ## Examples

      iex> Bonfire.Boundaries.Acls.set(%{}, creator, [boundary: "local"])
      {:ok, :granted}
  """
  def set(object, creator, opts)
      when is_list(opts) and is_struct(object) do
    with {_num, nil} <- do_set(object, creator, opts) do
      {:ok, :granted}
    end
  end

  @doc """
  Previews ACLs as they would be set based on provided opts.

  ## Examples

      iex> Bonfire.Boundaries.Acls.preview(creator, [
        preview_for_id: object_id,
        boundary: "mentions",
        to_circles: mentioned_users_or_custom_circles
      ])

      iex> Bonfire.Boundaries.Acls.preview(creator, [
        preview_for_id: object_id,
        boundary: "clone_context",
        context_id: context_object_id
      ])

  """
  def preview(creator, opts)
      when is_list(opts) do
    with {:error, {:ok, [%{verbs: verbs}]}} <- do_preview(creator, opts) do
      {:ok, verbs}
    else
      {:error, {:ok, []}} ->
        {:ok, []}

      other ->
        error(other)
    end
  end

  defp do_preview(creator, opts) do
    object = generate_object()

    repo().transaction(fn _repo ->
      do_set(object, creator, opts)

      repo().rollback(
        {:ok,
         Bonfire.Boundaries.users_grants_on(
           opts[:preview_for_id] || Circles.get_id!(:guest),
           object
         )}
      )
    end)
  end

  defp generate_object do
    Needle.Pointer.create(Bonfire.Data.Social.Post)
    |> Bonfire.Common.Repo.insert!()
  end

  defp do_set(object, creator, opts) do
    id = uid(object)

    # Needle.ULID.as_uuid(id) |> debug("oooid for #{id}")

    case prepare_cast(object, creator, opts) do
      {:ok, control_acls} ->
        control_acls

      {fun, control_acls} when is_function(fun) ->
        fun.(repo())

        control_acls
    end
    |> Enum.map(&Map.put(&1, :id, id))
    |> debug("insert controlled")
    |> repo().insert_all(Controlled, ..., on_conflict: :nothing)
    |> debug("inserted?")
  end

  @doc """
  Casts ACLs (existing ones or creating some on-the-fly) and Controlled on an object.

  ## Examples

      iex> Bonfire.Boundaries.Acls.cast(changeset, creator, [boundary: "local"])
  """
  def cast(changeset, creator, opts) do
    object_id = uid(changeset) || "no_id"
    debug("=== cast CALLED for object #{object_id} ===")

    case prepare_cast(changeset, creator, opts) do
      {:ok, control_acls} ->
        debug("=== cast: putting assoc for #{object_id} ===")
        Changesets.put_assoc(changeset, :controlled, control_acls)

      {fun, control_acls} when is_function(fun) ->
        debug("=== cast: using prepare_changes for #{object_id} ===")

        changeset
        |> Changeset.prepare_changes(fun)
        |> Changesets.put_assoc!(:controlled, control_acls)
    end
    |> debug("after cast")
  end

  def prepare_cast(changeset_or_obj, creator, opts) do
    object_id =
      uid(changeset_or_obj) ||
        "no_id"
        |> debug("=== prepare_cast CALLED for object ===")

    # debug(Process.info(self(), :current_stacktrace), "stacktrace")

    # opts
    # |> debug("cast opts")

    context_id = maybe_from_opts(opts, :context_id)

    {preset, control_acls} =
      case maybe_from_opts(opts, :boundary, opts) do
        {:clone, controlled_object_id} ->
          copy_acls_from_existing_object(controlled_object_id)

        ["clone_context"] when is_binary(context_id) ->
          copy_acls_from_existing_object(context_id)

        to_boundaries ->
          preset_acls_tuple(creator, to_boundaries, opts)
      end

    # debug(control_acls, "preset + inputted ACLs to set")
    # |> Enum.map(&Needle.ULID.as_uuid(&1.acl_id))
    # |> debug()

    verb_grants =
      case e(opts, :verb_grants, []) do
        verb_grants
        when is_list(verb_grants) or
               (is_map(verb_grants) and verb_grants != [] and verb_grants != %{}) ->
          verb_grants

        _ ->
          []
      end
      |> debug("verb_grants input")

    case custom_recipients(changeset_or_obj, preset, opts) do
      [] when verb_grants == [] ->
        debug("=== prepare_cast RETURNING {:ok, control_acls} for #{object_id} ===")
        {:ok, control_acls}

      custom_recipients ->
        debug(custom_recipients, "custom_recipients for #{object_id}")

        # TODO: enable using cast on existing objects by using `get_or_create_object_custom_acl(object)` to check if a custom Acl already exists?
        acl_id = Needle.UID.generate(Acl)
        debug("=== GENERATED ACL ID: #{acl_id} for object #{object_id} ===")

        # default_role = e(opts, :role_to_grant, nil) || Config.get!([:role_to_grant, :default])

        # Process default verbs for all recipients
        custom_recipient_grants =
          (e(opts, :verbs_to_grant, nil) ||
             Config.get!([:verbs_to_grant, :default]))
          |> debug("default verbs_to_grant")
          |> Enum.flat_map(custom_recipients, &grant_to(&1, acl_id, ..., true, opts))

        # Process direct verb grants (bypasses role system)

        direct_grants =
          verb_grants
          |> Enum.flat_map(fn {subject_id, verb, value} ->
            grant_to(subject_id, acl_id, verb, value, opts)
          end)
          |> debug("direct_grants output")

        # Deduplicate grants - direct_grants override default_grants for same subject+verb
        unique_custom_acl_grants =
          if direct_grants == [] do
            custom_recipient_grants
          else
            # Create a map key for deduplication
            direct_keys =
              direct_grants
              |> Enum.map(fn grant ->
                {grant.subject_id, grant.verb_id}
              end)
              |> MapSet.new()

            # Keep only default grants that don't conflict with direct grants
            filtered_defaults =
              custom_recipient_grants
              |> Enum.reject(fn grant ->
                MapSet.member?(direct_keys, {grant.subject_id, grant.verb_id})
              end)

            filtered_defaults ++ direct_grants
          end
          |> debug("all custom grants")
          |> Grants.uniq_grants_to_create()
          |> debug("on-the-fly unique ACLs to create")

        debug("=== prepare_cast RETURNING {fun, control_acls} for #{object_id} ===")

        {
          fn changeset ->
            debug("=== EXECUTING INSERT FUNCTION for ACL #{acl_id} ===")
            insert_custom_acl_and_grants(changeset, acl_id, unique_custom_acl_grants)

            changeset
            |> debug("returning changeset from prepare_changes")
          end,
          [%{acl_id: acl_id} | control_acls]
        }
    end
  end

  defp preset_acls_tuple(creator, to_boundaries, opts \\ []) do
    {preset, base_acls, direct_acl_ids} =
      preset_stereotypes_and_acls(
        creator,
        to_boundaries,
        opts
        |> Keyword.put_new_lazy(:universal_boundaries, fn ->
          Config.get!([:object_default_boundaries, :acls])
        end)
      )

    {preset,
     Enum.map(
       find_acls(base_acls, creator) ++ direct_acl_ids,
       &%{acl_id: id(&1)}
     )}
  end

  def acls_from_preset(creator, to_boundaries, opts \\ []) do
    {_preset, base_acls, direct_acl_ids} =
      preset_stereotypes_and_acls(
        creator,
        to_boundaries,
        opts
      )

    find_acls(base_acls, creator) ++ list(ids: direct_acl_ids, current_user: creator)
  end

  def grant_tuples_from_preset(creator, to_boundaries, opts \\ []) do
    {_preset, base_acls, direct_acl_ids} =
      preset_stereotypes_and_acls(
        creator,
        to_boundaries,
        opts
      )

    # list(ids: direct_acl_ids, current_user: creator)
    # |> repo().maybe_preload(:grants)
    (Grants.get(base_acls)
     |> Enum.flat_map(
       &Enum.map(
         &1,
         fn {slug, role} ->
           {Circles.get(slug), role}
         end
       )
     )) ++
      (Grants.list_for_acl(direct_acl_ids, current_user: creator, skip_boundary_check: true)
       |> Grants.grants_to_tuples(creator, ...))
  end

  defp preset_stereotypes_and_acls(creator, to_boundaries, opts \\ []) do
    {to_boundaries, preset} = to_boundaries_preset_tuple(to_boundaries)

    # add ACLs based on any boundary presets (eg. public/local/mentions)
    # + add any ACLs directly specified in input

    {preset, base_acls(creator, preset, opts), maybe_add_direct_acl_ids(to_boundaries)}
  end

  defp to_boundaries_preset_tuple(to_boundaries) do
    to_boundaries =
      Boundaries.boundaries_normalise(to_boundaries)
      |> debug("validated to_boundaries")

    preset =
      Boundaries.preset_name(to_boundaries)
      |> debug("preset_name")

    {to_boundaries, preset}
  end

  def base_acls_from_preset(creator, preset, opts \\ []) do
    {_preset, control_acls} = preset_acls_tuple(creator, preset, opts)
    control_acls
  end

  # when the user picks a preset, this maps to a set of base acls
  defp base_acls(_user, preset, opts) do
    (List.wrap(opts[:universal_boundaries]) ++
       Boundaries.acls_from_preset_boundary_names(preset))
    |> info("preset ACLs to set (based on preset #{preset}) ")
  end

  defp maybe_add_direct_acl_ids(acls) do
    uids(acls)
    |> filter_empty([])
  end

  defp custom_recipients(changeset_or_obj, preset, opts) do
    (List.wrap(reply_to_grants(changeset_or_obj, preset, opts)) ++
       List.wrap(mentions_grants(changeset_or_obj, preset, opts)) ++
       List.wrap(maybe_custom_circles_or_users(maybe_from_opts(opts, :to_circles, []))))
    |> debug("custom_recipients input")
    |> Enum.map(fn
      nil -> nil
      {nil, nil} -> nil
      {subject, role} -> {subject, if(preset != "mentions", do: Types.maybe_to_atom!(role))}
      subject -> {subject, nil}
    end)
    # |> debug()
    |> Enum.reject(&is_nil/1)
    # |> debug()
    # NOTE: cannot do this or we don't allow same user with multiple roles:
    # |> Enum.sort_by(fn {_subject, role} -> role end, :desc)
    # |> Enum.uniq_by(fn {subject, _role} -> subject end)
    # we just keep a unique combo then:
    |> Enum.uniq()
    # |> debug()
    |> debug("custom_recipients output")
  end

  defp maybe_custom_circles_or_users(to_circles) when is_list(to_circles) or is_map(to_circles) do
    to_circles
    |> debug("to_circles input")
    |> Enum.map(fn
      {circle, val} when is_atom(circle) ->
        {Circles.get_id!(circle), val}

      {key, val} ->
        # with custom role
        case uid(key) do
          nil -> {uid(val), key}
          subject_id -> {subject_id, val}
        end

      val ->
        uid(val)
    end)
    |> debug("maybe_custom_circles_or_users output")
  end

  defp maybe_custom_circles_or_users(to_circles),
    do: maybe_custom_circles_or_users(List.wrap(to_circles))

  defp reply_to_grants(changeset_or_obj, preset, _opts) do
    reply_to_creator =
      e(
        changeset_or_obj,
        :changes,
        :replied,
        :changes,
        :replying_to,
        :created,
        :creator,
        nil
      ) ||
        e(
          changeset_or_obj,
          :replied,
          :reply_to,
          :created,
          :creator,
          nil
        )

    if reply_to_creator do
      # debug(reply_to_creator, "creators of reply_to should be added to a new ACL")

      case preset do
        "public" ->
          id(reply_to_creator)

        "local" ->
          if is_local?(reply_to_creator),
            do: id(reply_to_creator),
            else: []

        _ ->
          []
      end
    else
      []
    end
  end

  defp mentions_grants(changeset_or_obj, preset, _opts) do
    mentions =
      e(changeset_or_obj, :changes, :post_content, :changes, :mentions, nil) ||
        e(changeset_or_obj, :post_content, :mentions, nil)

    if mentions && mentions != [] do
      # debug(mentions, "mentions/tags may be added to a new ACL")

      case preset do
        "public" ->
          uids(mentions)

        "mentions" ->
          uids(mentions)

        "local" ->
          # include only if local
          mentions
          |> Enum.filter(&is_local?/1)
          |> uids()

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
    # is_local? = is_local?(user, exclude_service_character: true)
    is_local? = true

    # # FIXME: making this correct remote causes `Missing default acl: :my_ghosted_cannot_anything`

    acls =
      acls
      |> Enum.map(&identify(is_local?, &1))
      |> debug("identified")
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
          |> Boundaries.find_caretaker_stereotypes(user, ..., Acl)

          # |> info("stereos")
      end

    globals ++ stereo
  end

  defp find_acls(_acls, _) do
    warn("You need to provide an object creator to properly set ACLs")
    []
  end

  defp identify(local?, name) do
    case user_default_acl(local?, name) do
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

  defp grant_to(subject, acl_id, default_verbs, value, opts)

  defp grant_to({subject_id, nil}, acl_id, default_verbs, value, opts),
    do: grant_to(subject_id, acl_id, default_verbs, value, opts)

  defp grant_to({subject_id, roles}, acl_id, default_verbs, value, opts) when is_list(roles) do
    Enum.flat_map(roles, &grant_to({subject_id, &1}, acl_id, default_verbs, value, opts))
  end

  defp grant_to({subject_id, role}, acl_id, _default_verbs, _value, opts) do
    with {:ok, can_verbs, cannot_verbs} <- Roles.verbs_for_role(role, opts) do
      grant_to(subject_id, acl_id, can_verbs, true, opts) ++
        grant_to(subject_id, acl_id, cannot_verbs, false, opts)
    else
      e ->
        error(e)
        []
    end
  end

  defp grant_to(user_etc, acl_id, verbs, value, opts) when is_list(verbs),
    do: Enum.flat_map(verbs, &grant_to(user_etc, acl_id, &1, value, opts))

  defp grant_to(users_etc, acl_id, verb, value, opts) when is_list(users_etc),
    do: Enum.flat_map(users_etc, &grant_to(&1, acl_id, verb, value, opts))

  defp grant_to(user_etc, acl_id, verb, value, _opts) do
    debug(user_etc)

    [
      %{
        id: Needle.UID.generate(Grant),
        acl_id: acl_id,
        subject_id: user_etc,
        verb_id: Verbs.get_id!(verb),
        value: value
      }
    ]
  end

  def get_object_custom_acl(object) do
    from(a in Acl,
      join: c in Controlled,
      on: a.id == c.acl_id and c.id == ^uid(object),
      join: s in Stereotyped,
      on: a.id == s.id and s.stereotype_id == ^Scaffold.Instance.custom_acl(),
      preload: [stereotyped: s]
    )
    |> repo().single()

    # |> debug("custom acl")
  end

  def get_or_create_object_custom_acl(object, caretaker \\ nil) do
    case get_object_custom_acl(object) do
      {:ok, acl} ->
        {:ok, acl}

      _ ->
        with {:ok, acl} <-
               create(
                 prepare_custom_acl_maps(Needle.UID.generate(Acl)),
                 current_user: caretaker
               ),
             {:ok, _} <- Controlleds.add_acls(object, acl) do
          {:ok, acl}
        end
    end
  end

  defp insert_custom_acl_and_grants(repo_or_changeset \\ repo(), acl_id, custom_grants)

  defp insert_custom_acl_and_grants(%Ecto.Changeset{} = changeset, acl_id, custom_grants) do
    insert_custom_acl_and_grants(changeset.repo, acl_id, custom_grants)
  end

  defp insert_custom_acl_and_grants(repo, acl_id, custom_grants) when is_binary(acl_id) do
    # Check if ACL already exists before attempting to insert
    case repo.exists?(from a in Acl, where: a.id == ^acl_id) do
      false ->
        # ACL doesn't exist, create it
        prepare_custom_acl(acl_id)
        |> debug("custom acl")
        |> repo.insert!()
        |> debug("inserted custom acl")

      true ->
        # ACL already exists, skip creation
        debug("ACL #{acl_id} already exists, skipping creation")
    end

    # Always insert grants (they might be different even for existing ACLs)
    repo.insert_all_or_ignore(Grant, custom_grants)
    |> debug("inserted custom grants")
  end

  defp prepare_custom_acl(acl_id) do
    %Acl{
      id: acl_id,
      stereotyped: %Stereotyped{id: acl_id, stereotype_id: Scaffold.Instance.custom_acl()}
    }
  end

  defp prepare_custom_acl_maps(acl_id) do
    %{
      id: acl_id,
      stereotyped: %{id: acl_id, stereotype_id: Scaffold.Instance.custom_acl()}
    }
  end

  defp copy_acls_from_existing_object(controlled_object_id) do
    {nil,
     Controlleds.list_on_object(controlled_object_id)
     |> Enum.map(&Map.take(&1, [:acl_id]))
     |> debug()}
  end

  ## invariants:

  ## * All a user's ACLs will have the user as an administrator but it
  ##   will be hidden from the user

  @doc """
  Creates a new ACL.

  ## Examples

      iex> Bonfire.Boundaries.Acls.create(%{named: %{name: "New ACL"}}, current_user: user)
      {:ok, %Acl{}}
  """
  def create(attrs \\ %{}, opts) do
    attrs
    |> input_to_atoms()
    |> changeset(:create, ..., opts)
    |> repo().insert()
  end

  @doc """
  Creates a simple ACL with a name.

  ## Examples

      iex> Bonfire.Boundaries.Acls.simple_create(user, "My ACL")
      {:ok, %Acl{}}
  """
  def simple_create(caretaker, name) do
    create(%{named: %{name: name}}, current_user: caretaker)
  end

  def changeset(:create, attrs, opts) do
    changeset(:create, attrs, opts, Keyword.fetch!(opts, :current_user))
  end

  defp changeset(:create, attrs, _opts, :system), do: changeset_cast(attrs)

  defp changeset(:create, attrs, opts, instance) when instance in [:instance, :instance_wide],
    do:
      changeset(:create, attrs, opts, %{
        id: Bonfire.Boundaries.Scaffold.Instance.admin_circle()
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

  @doc """
  Retrieves an ACL for a caretaker.

  ## Examples

      iex> Bonfire.Boundaries.Acls.get_for_caretaker("ACL_ID", user)
      {:ok, %Acl{}}
  """
  def get_for_caretaker(id, caretaker, opts \\ []) do
    with {:ok, acl} <- repo().single(get_for_caretaker_q(id, caretaker, opts)) do
      {:ok, acl}
    else
      {:error, :not_found} ->
        if Bonfire.Boundaries.can?(current_account(opts) || caretaker, :assign, :instance),
          do:
            repo().single(
              get_for_caretaker_q(
                id,
                Bonfire.Boundaries.Scaffold.Instance.admin_circle(),
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
    if is_built_in?(id) do
      where(query, [acl], acl.id == ^uid!(id))
    else
      # |> reusable_join(:inner, [circle: circle], caretaker in assoc(circle, :caretaker), as: :caretaker)
      where(
        query,
        [acl, caretaker: caretaker],
        acl.id == ^uid!(id) and caretaker.caretaker_id == ^uid!(caretaker)
      )
    end
  end

  @doc """
  Lists ACLs the current user is permitted to see.

  ## Examples

      iex> Bonfire.Boundaries.Acls.list(current_user: user)
      [%Acl{}, %Acl{}]
  """
  def list(opts \\ []) do
    list_q(opts)
    |> where(
      [caretaker: caretaker],
      caretaker.caretaker_id in ^[current_user_id(opts), Scaffold.Instance.admin_circle()]
    )
    |> many_with_opts(opts)
  end

  def list_q(opts \\ []) do
    from(acl in Acl, as: :acl)
    # |> boundarise(acl.id, opts)
    |> proload([
      :caretaker,
      :named,
      :extra_info,
      stereotyped: {"stereotype_", [:named]}
    ])
    |> maybe_by_ids(opts[:ids])
    |> maybe_search(opts[:search])
  end

  def maybe_by_ids(query, ids) when is_binary(ids) or is_list(ids) do
    query
    |> where(
      [acl],
      acl.id in ^Types.uids(ids)
    )
  end

  def maybe_by_ids(query, _), do: query

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
  # |> many_with_opts(opts)
  # end

  @doc """
  Returns a list of built-in ACL IDs.

  ## Examples

      iex> Bonfire.Boundaries.Acls.built_in_ids()
      ["BUILT_IN_ACL_ID1", "BUILT_IN_ACL_ID2"]
  """
  def built_in_ids do
    acls()
    |> Map.values()
    |> Enums.ids()
  end

  @doc """
  Returns a list of stereotype ACL IDs.

  ## Examples

      iex> Bonfire.Boundaries.Acls.stereotype_ids()
      ["STEREOTYPE_ACL_ID1", "STEREOTYPE_ACL_ID2"]
  """
  def stereotype_ids do
    acls()
    |> Map.values()
    |> Enum.filter(&e(&1, :stereotype, nil))
    |> Enums.ids()
  end

  @doc """
  Checks if an ACL is stereotyped.

  ## Examples

      iex> Bonfire.Boundaries.Acls.is_stereotyped?(%Acl{stereotyped: %{stereotype_id: "STEREOTYPE_ID"}})
      true

      iex> Bonfire.Boundaries.Acls.is_stereotyped?("STEREOTYPE_ID")
      true

      iex> Bonfire.Boundaries.Acls.is_stereotyped?(%Acl{})
      false
  """
  def is_stereotyped?(%{stereotyped: %{stereotype_id: stereotype_id}} = _acl)
      when is_binary(stereotype_id) do
    true
  end

  def is_stereotyped?(_acl) do
    false
  end

  def is_stereotype?(acl) do
    # debug(acl)
    uid(acl) in stereotype_ids()
  end

  @doc """
  Checks if an ACL is built-in.

  ## Examples

      iex> Bonfire.Boundaries.Acls.is_built_in?("BUILT_IN_ACL_ID")
      true

      iex> Bonfire.Boundaries.Acls.is_built_in?("CUSTOM_ACL_ID")
      false
  """
  def is_built_in?(acl) do
    # debug(acl)
    uid(acl) in built_in_ids()
  end

  @doc """
  Checks if an ACL is a custom ACL for an object.

  ## Examples

      iex> Bonfire.Boundaries.Acls.is_object_custom?(%Acl{stereotyped: %{stereotype_id: "CUSTOM_ACL_ID"}})
      true

      iex> Bonfire.Boundaries.Acls.is_object_custom?(%Acl{})
      false
  """
  def is_object_custom?(%{stereotyped: %{stereotype_id: stereotype_id}} = _acl)
      when is_binary(stereotype_id) do
    is_object_custom?(stereotype_id)
    |> debug(stereotype_id)
  end

  def is_object_custom?(acl) do
    id(acl) == Scaffold.Instance.custom_acl()
  end

  @doc """
  Lists built-in ACLs.

  ## Examples

      iex> Bonfire.Boundaries.Acls.list_built_ins()
      [%Acl{}, %Acl{}]
  """
  def list_built_ins(opts \\ []) do
    list_q(skip_boundary_check: true)
    |> where([acl], acl.id in ^built_in_ids())
    |> many_with_opts(opts)
  end

  # TODO
  defp built_ins_for_dropdown do
    filter = Config.get(:acls_for_dropdown)

    acls()
    |> Enum.filter(fn {name, _acl} -> name in filter end)
    |> Enum.map(fn {_name, acl} -> acl.id end)
  end

  @doc """
  Returns options to use when querying for ACLs to show in a dropdown in the UI.

  ## Examples

      iex> Bonfire.Boundaries.Acls.opts_for_dropdown()
      [exclude_ids: [...], extra_ids_to_include: [...]]
  """
  def opts_for_dropdown() do
    opts_for_list() ++
      [
        extra_ids_to_include: built_ins_for_dropdown()
      ]
  end

  @doc """
  Returns options to use when querying for ACLs to show in a list.

  ## Examples

      iex> Bonfire.Boundaries.Acls.opts_for_list()
      [exclude_ids: [...]]
  """
  def opts_for_list() do
    [
      exclude_ids: default_exclude_ids()
    ]
  end

  # def for_dropdown(opts) do
  #   list_my_with_counts(current_user(opts), opts ++ opts_for_dropdown())
  # end

  defp many_with_opts(query, opts) do
    query
    |> many(opts[:paginate?], opts)
    |> maybe_preload_n_subjects(opts[:preload_n_subjects])
  end

  @doc """
  Lists ACLs for a specific user.

  Includes the ACLs we are the registered caretakers of that we are
  permitted to see. If any are created without permitting the
  user to see them, they will not be shown.

  ## Examples

      iex> Bonfire.Boundaries.Acls.list_my(user)
      [%Acl{}, %Acl{}]
  """
  def list_my(user, opts \\ [])

  def list_my(:instance, opts),
    do: list_my(Bonfire.Boundaries.Scaffold.Instance.admin_circle(), opts)

  def list_my(user, opts),
    do:
      list_my_q(user, opts)
      |> many_with_opts(opts)

  @doc """
  Lists ACLs for a specific user with grant counts (how many rules ).

  ## Examples

      iex> Bonfire.Boundaries.Acls.list_my_with_counts(user)
      [%{acl: %Acl{}, grants_count: 5}, %{acl: %Acl{}, grants_count: 2}]
  """
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
    |> select_merge([grants: grants], %{
      grants_count: grants.count
    })
    # because otherwise we need to handle special cursors for pagination
    |> q_maybe_order(!opts[:paginate?])
    |> many_with_opts(opts)
  end

  defp q_maybe_order(query, true) do
    query
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
    |> select_merge([controlled: controlled], %{
      controlled_count: controlled.count
    })
    |> order_by(
      [
        controlled: controlled,
        grants: grants
      ],
      desc_nulls_last: controlled.count,
      desc_nulls_last: grants.count
    )
  end

  defp q_maybe_order(query, _), do: query

  @doc "query for `list_my`"
  def list_my_q(user, opts \\ []) do
    exclude =
      e(
        opts,
        :exclude_ids,
        exclude_stereotypes(
          e(
            opts,
            :exclude_stereotypes,
            nil
          )
        )
      )

    list_q(skip_boundary_check: true)
    |> where(
      [acl, caretaker: caretaker],
      caretaker.caretaker_id == ^uid!(user) or
        (acl.id in ^e(opts, :extra_ids_to_include, []) and
           acl.id not in ^exclude)
    )
    |> where(
      [stereotyped: stereotyped],
      is_nil(stereotyped.id) or
        stereotyped.stereotype_id not in ^exclude
    )
  end

  defp maybe_preload_n_subjects(acls, limit) when is_integer(limit) and limit > 0 do
    grant_query = from g in Grant, limit: ^limit
    pointer_query = from p in Pointer, limit: ^limit

    repo().maybe_preload(
      acls,
      grants:
        {grant_query,
         [
           # :verb,
           subject:
             {pointer_query,
              [
                :named,
                :profile,
                # encircle_subjects: [:profile],
                stereotyped: [:named]
              ]}
         ]}
    )
  end

  defp maybe_preload_n_subjects(acls, _), do: acls

  def user_default_acl(local?, name), do: user_default_acls(local?)[name]

  # FIXME: this vs acls/0 ?
  def user_default_acls(local?) do
    Map.fetch!(Boundaries.user_default_boundaries(local?), :acls)
    # |> debug
  end

  def acl_grants_to_tuples(creator, acls) when is_list(acls) do
    acls
    |> Enum.flat_map(fn %{grants: grants} -> grants end)
    |> Grants.grants_to_tuples(creator, ...)
  end

  def acl_grants_to_tuples(creator, %{grants: grants}),
    do: Grants.grants_to_tuples(creator, grants)

  @doc """
  Edits an existing ACL.

  ## Examples

      iex> Bonfire.Boundaries.Acls.edit(acl_id, user, %{name: "Updated ACL"})

      iex> Bonfire.Boundaries.Acls.edit(%Acl{}, user, %{name: "Updated ACL"})
  """
  def edit(%Acl{} = acl, %User{} = _user, params) do
    # TODO: check edit permission
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

    Bonfire.Common.Utils.maybe_apply(
      Bonfire.Social.Objects,
      :maybe_generic_delete,
      [Acl, acl, [current_user: current_user(opts), delete_associations: assocs]]
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
