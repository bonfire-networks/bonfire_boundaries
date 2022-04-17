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
  alias Bonfire.Data.Identity.Named
  alias Bonfire.Data.Identity.Caretaker
  alias Bonfire.Boundaries.Stereotyped
  alias Bonfire.Data.AccessControl.{Acl, Controlled, Grant}
  alias Bonfire.Data.Identity.User
  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Verbs
  alias Ecto.Changeset
  alias Pointers.{Changesets, ULID}

  def cast(changeset, creator, preset_or_custom) do
    id = Changeset.get_field(changeset, :id)
    base = base_acls(creator, preset_or_custom)
    case custom_grants(changeset, preset_or_custom) do
      [] ->
        changeset
        |> Changesets.put_assoc(:controlled, base)
      grants ->
        acl_id = ULID.generate()
        controlled = [%{acl_id: acl_id} | base]
        grants = Enum.flat_map(grants, &grant_to(ulid(&1), acl_id))
        changeset
        |> Changeset.prepare_changes(fn changeset ->
          changeset.repo.insert!(%Acl{id: acl_id})
          changeset.repo.insert_all(Grant, grants)
          changeset
        end)
        |> Changesets.put_assoc(:controlled, controlled)
    end
  end

  # when the user picks a preset, this maps to a set of base acls
  defp base_acls(user, preset_or_custom) do
    acls = (
      Config.get!([:object_default_boundaries, :acls])
      ++
      case Boundaries.preset(preset_or_custom) do
        "public"    -> [:guests_may_see_read,  :locals_may_reply]
        "federated" -> [:locals_may_reply]
        "local"     -> [:locals_may_reply]
        _           -> []
      end
    )
    # |> dump
    |> find_acls(user)
    # |> dump
  end

  defp custom_grants(changeset, preset_or_custom) do
    (
      reply_to_grants(changeset, preset_or_custom)
      ++ mentions_grants(changeset, preset_or_custom)
      ++ Boundaries.maybe_custom_circles_or_users(preset_or_custom)
    )
    |> Enum.uniq()
    |> filter_empty([])
  end

  defp reply_to_grants(changeset, preset_or_custom) do
    reply_to_creator = Utils.e(changeset, :changes, :replied, :changes, :replying_to, :created, :creator, nil)

    if reply_to_creator do
      # debug(reply_to_creator, "creators of reply_to should be added to a new ACL")

      case Boundaries.preset(preset_or_custom) do
        "public" ->
          [ulid(reply_to_creator)]
        "local" ->
          if is_local?(reply_to_creator), do: [Utils.e(reply_to_creator, :id, nil)],
          else: []
        _ -> []
      end
    else
      []
    end
  end

  defp mentions_grants(changeset, preset_or_custom) do
    mentions = Utils.e(changeset, :changes, :post_content, :changes, :mentions, nil)

    if mentions && mentions !=[] do
      # debug(mentions, "mentions/tags should be added to a new ACL")

      case Boundaries.preset(preset_or_custom) do
        "public" ->
          ulid(mentions)
        "mentions" ->
          ulid(mentions)
        "local" ->
          ( # include only if local
            mentions
            |> Enum.filter(&is_local?/1)
            |> ulid()
          )
        _ ->
        []
      end
    else
      []
    end
  end

  defp find_acls(acls, user) when is_list(acls) and length(acls)>0 and ( is_binary(user) or is_map(user) ) do
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
        [] -> []
        stereo ->
          stereo
          |> Enum.map(&elem(&1, 1).id)
          |> Acls.find_caretaker_stereotypes(user, ...)
          # |> info("stereos")
      end
    Enum.map(globals ++ stereo, &(%{acl_id: &1.id}))
  end
  defp find_acls(_acls, _) do
    warn("You need to provide an object creator to properly set ACLs")
    []
  end

  defp identify(name) do
    case user_default_acl(name) do

      nil -> # seems to be a global ACL
        {:global, Acls.get!(name)}

      default -> # should be a user-level stereotyped ACL
        case default[:stereotype] do
          nil -> raise RuntimeError, message: "Boundaries: Unstereotyped user acl in config: #{inspect(name)}"
          stereo -> {:stereo, Acls.get!(stereo)}
        end
    end
  end

  defp grant_to(user_etc, acl_id) do
    [:see, :read]
    |> Enum.map(&grant_to(user_etc, acl_id, &1))
  end

  defp grant_to(user_etc, acl_id, verb) do
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
    changeset(:create, attrs, opts)
    |> repo().insert()
  end

  def changeset(:create, attrs, opts) do
    changeset(:create, attrs, opts, Keyword.fetch!(opts, :current_user))
  end

  defp changeset(:create, attrs, opts, :system), do: Acls.changeset(attrs)
  defp changeset(:create, attrs, opts, %{id: id}) do
    Changeset.cast(%Acl{}, %{caretaker: %{caretaker_id: id}}, [])
    |> changeset_cast(attrs)
  end

  def changeset_cast(acl \\ %Acl{}, attrs) do
    Acl.changeset(acl, attrs)
    # |> IO.inspect(label: "cs")
    |> Changeset.cast_assoc(:named, [])
    |> Changeset.cast_assoc(:caretaker)
    |> Changeset.cast_assoc(:stereotyped)
  end


  @doc """
  Lists ACLs we are permitted to see.
  """
  def list(opts) do
    list_q(opts)
    |> repo().many()
  end

  def list_q(opts) do
    from(acl in Acl, as: :acl)
    |> boundarise(acl.id, opts)
    |> proload([:caretaker, :named, :stereotyped])
  end

  @doc """
  Lists the ACLs we are the registered caretakers of that we are
  permitted to see. If any are created without permitting the
  user to see them, they will not be shown.
  """
  def list_my(%{}=user), do: repo().many(list_my_q(user))

  @doc "query for `list_my`"
  def list_my_q(%{id: user_id}=user) do
    list_q(user)
    |> where([caretaker: caretaker], caretaker.caretaker_id == ^user_id)
  end

  # special built-in acls (eg, guest, local, activity_pub)
  def acls, do: Bonfire.Common.Config.get([:acls])

  def user_default_acl(name), do: user_default_acls()[name]

  def user_default_acls() do # FIXME: this vs acls/0 ?
    Boundaries.user_default_boundaries()
    |> Map.fetch!(:acls)
    # |> dump
  end

  def get(slug) when is_atom(slug), do: acls()[slug]
  def get!(slug) when is_atom(slug) do
    get(slug)
      # || ( Bonfire.Boundaries.Fixtures.insert && get(slug) )
      || raise RuntimeError, message: "Missing default acl: #{inspect(slug)}"
  end

  def get_id(slug), do: e(acls(), slug, :id, nil)
  def get_id!(slug), do: get!(slug)[:id]

  def list do
    from(u in Acl, as: :acl)
    |> proload([:named, :controlled, :stereotyped, :caretaker])
    |> repo().many()
  end

  def find_caretaker_stereotypes(caretaker, stereotypes) do
    from(a in Acl,
      join: c in Caretaker,  on: a.id == c.id and c.caretaker_id == ^ulid(caretaker),
      join: s in Stereotyped, on: a.id == s.id and s.stereotype_id in ^stereotypes,
      preload: [caretaker: c, stereotyped: s]
    ) |> repo().all()
    # |> debug("stereotype acls")
  end

end
