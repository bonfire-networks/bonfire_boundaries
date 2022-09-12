defmodule Bonfire.Boundaries.Grants do
  @moduledoc """
  a grant applies to a subject
  """
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Queries
  import Bonfire.Boundaries.Integration
  import Ecto.Query

  # import EctoSparkles

  alias Ecto.Changeset
  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.Identity.User
  # alias Bonfire.Data.AccessControl.Accesses
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Grants
  # alias Bonfire.Boundaries.Accesses
  alias Bonfire.Boundaries.Circles

  def grants, do: Config.get([:grants])

  ## invariants:

  ## * All a user's GRANTs will have the user as an administrator but it
  ##   will be hidden from the user

  def create(attrs, opts) do
    changeset(:create, attrs, opts)
    |> repo().insert()

    # |> debug("Me.Grants - granted")
  end

  def create(%{} = attrs) when not is_struct(attrs) do
    repo().insert(changeset(attrs))
  end

  def changeset(grant \\ %Grant{}, attrs) do
    Grant.changeset(grant, attrs)
    |> Changeset.cast_assoc(:caretaker)
  end

  def changeset(:create, attrs, opts) do
    changeset(:create, attrs, opts, Keyword.fetch!(opts, :current_user))
  end

  defp changeset(:create, attrs, _opts, :system), do: changeset(attrs)

  defp changeset(:create, attrs, _opts, %{id: id}) do
    Changeset.cast(%Grant{}, %{caretaker: %{caretaker_id: id}}, [])
    |> changeset(attrs)
  end

  def upsert_or_delete(
        %{acl_id: acl_id, subject_id: subject_id, verb_id: verb_id, value: nil} = attrs,
        opts
      ) do
    repo().get_by(Grant,
      acl_id: acl_id,
      subject_id: subject_id,
      verb_id: verb_id
    )
    # |> debug
    |> repo().delete()
  end

  def upsert_or_delete(%{} = attrs, opts) do
    repo().upsert(
      changeset(attrs),
      attrs,
      [:acl_id, :subject_id, :verb_id]
    )
  end

  @doc """
  Grant takes three parameters:
  - subject_id:  who we are granting access to
  - acl_id: what ACL we're applying a grant to
  - verb: which verb/action
  - value: true, false, or nil
  """
  def grant(subject_id, acl_id, verb, value, opts \\ [])

  # |> debug("mapped") # TODO: optimise?
  def grant(subject_ids, acl_id, verb, value, opts) when is_list(subject_ids),
    do:
      subject_ids
      |> Circles.circle_ids()
      |> Enum.map(&grant(&1, acl_id, verb, value, opts))

  # |> debug("mapped") # TODO: optimise?
  def grant(subject_id, acl_id, verbs, value, opts) when is_list(verbs),
    do: Enum.map(verbs, &grant(subject_id, acl_id, &1, value, opts))

  def grant(subject_id, acl_id, verb, value, opts)
      when is_atom(verb) and not is_nil(verb) do
    debug("Me.Grants - lookup verb #{inspect(verb)}")
    grant(subject_id, acl_id, Config.get(:verbs)[verb][:id], value, opts)
  end

  def grant(subject_id, acl, verb_id, value, opts)
      when is_binary(subject_id) and is_binary(verb_id) do
    value =
      case value do
        1 -> true
        "1" -> true
        true -> true
        0 -> false
        "0" -> false
        false -> false
        _ -> nil
      end
      |> debug("grant value")

    upsert_or_delete(
      %{
        subject_id: subject_id,
        acl_id: ulid!(acl),
        verb_id: verb_id,
        value: value
      },
      opts
    )
  end

  def grant(subject_id, acl_id, access, value, opts)
      when not is_nil(subject_id) do
    subject_id
    |> Circles.circle_ids()
    |> grant(acl_id, access, value, opts)
  end

  def grant(_, _, _, _, _) do
    error("No function matched")
    nil
  end

  def remove_subject_from_acl(subject, acls)
      when is_nil(acls) or (is_list(acls) and length(acls) == 0),
      do: error("No circle ID provided, so could not remove")

  def remove_subject_from_acl(subject, acls) when is_list(acls) do
    from(e in Grant,
      where: e.subject_id == ^ulid(subject) and e.acl_id in ^ulid(acls)
    )
    |> repo().delete_all()
  end

  def remove_subject_from_acl(subject, acl) do
    remove_subject_from_acl(subject, [acl])
  end

  @doc """
  Lists the grants permitted to see.
  """
  def list(opts) do
    list_q(opts)
    |> preload(:named)
    |> repo().many()
  end

  def list_q(opts), do: list_q(Keyword.fetch!(opts, :current_user), opts)
  defp list_q(:system, _opts), do: from(grant in Grant, as: :grant)

  defp list_q(%User{}, opts),
    do: boundarise(list_q(:system, opts), grant.id, opts)

  @doc """
  Lists the grants we are the registered caretakers of that we are
  permitted to see. If any are created without permitting the
  user to see them, they will not be shown.
  """
  def list_my(%{} = user), do: repo().many(list_my_q(user))

  @doc "query for `list_my`"
  def list_my_q(%{id: user_id} = user) do
    list_q(user)
    |> join(:inner, [grant: grant], caretaker in assoc(grant, :caretaker), as: :caretaker)
    |> where([caretaker: caretaker], caretaker.caretaker_id == ^user_id)
  end
end
