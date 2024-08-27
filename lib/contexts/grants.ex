defmodule Bonfire.Boundaries.Grants do
  @moduledoc """
  A grant defines a permission (`value` boolean on a `Verb`) for a subject, within the context of an `Acl`. It defines the access rights for a specific user or circle in relation to a particular action.

  A permission is a decision about whether the action may be performed or not. There are 3 possible values:

  * `true`: yes, the action is allowed
  * `false`: no, the action is explicitly denied (i.e. never permit)
  * `null`/`nil`: unknown, the action isn't explicitly allowed (defaults to not allowed) 

  The corresponding Ecto schema is `Bonfire.Data.AccessControl.Grant` which is defined in a [seperate repo](https://github.com/bonfire-networks/bonfire_data_access_control).

  """
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Queries
  import Bonfire.Boundaries.Integration
  import Ecto.Query
  import EctoSparkles

  alias Ecto.Changeset
  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.Identity.User
  # alias Bonfire.Data.AccessControl.Accesses
  alias Bonfire.Boundaries.Circles
  # alias Bonfire.Boundaries.Grants
  # alias Bonfire.Boundaries.Verbs
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Roles

  @doc """
  Gets the configuration for grants.

  ## Examples

      iex> Bonfire.Boundaries.Grants.grants()
      %{}
  """
  def grants, do: Config.get([:grants])

  @doc """
  Gets the grant configuration by a given slug.

  ## Examples

      iex> Bonfire.Boundaries.Grants.get(:guests_may_see_read)
  """
  def get(slug) when is_atom(slug), do: Config.get([:grants, slug])
  def get(slugs) when is_list(slugs), do: Enum.map(slugs, &get/1)

  ## invariants:

  ## * All a user's GRANTs will have the user as an administrator but it
  ##   will be hidden from the user

  @doc """
  Creates a new grant with the given attributes and options.

  ## Examples

      iex> Bonfire.Boundaries.Grants.create(%{subject_id: "123", acl_id: "456", verb_id: "789", value: true}, [])
      {:ok, %Grant{}}
  """
  def create(attrs, opts \\ []) do
    changeset(:create, attrs, opts)
    |> repo().insert()

    # |> debug("Me.Grants - granted")
  end

  defp changeset(grant \\ %Grant{}, attrs) do
    Grant.changeset(grant, attrs)
    |> Changeset.cast_assoc(:caretaker)
  end

  defp changeset(:create, attrs, opts) do
    changeset(:create, attrs, opts, Keyword.fetch!(opts, :current_user))
  end

  defp changeset(:create, attrs, _opts, :system) when not is_struct(attrs), do: changeset(attrs)

  defp changeset(:create, attrs, _opts, %{id: id}) when not is_struct(attrs) do
    Changeset.cast(%Grant{}, %{caretaker: %{caretaker_id: id}}, [])
    |> changeset(attrs)
  end

  @doc """
  Inserts, updates, or deletes a grant based on the given attributes and options.

  ## Examples

      iex> Bonfire.Boundaries.Grants.upsert_or_delete(%{acl_id: "456", subject_id: "123", verb_id: "789", value: true}, [])
      {:ok, %Grant{}}

      iex> Bonfire.Boundaries.Grants.upsert_or_delete(%{acl_id: "456", subject_id: "123", verb_id: "789", value: nil}, [])
      {:ok, _deleted}
  """
  def upsert_or_delete(
        %{acl_id: acl_id, subject_id: subject_id, verb_id: verb_id, value: nil} = _attrs,
        _opts
      ) do
    repo().get_by(Grant,
      acl_id: acl_id,
      subject_id: subject_id,
      verb_id: verb_id
    )
    # |> debug
    |> repo().delete()
  end

  def upsert_or_delete(%{} = attrs, _opts) do
    repo().upsert(
      changeset(attrs),
      attrs,
      [:acl_id, :subject_id, :verb_id]
    )
  end

  @doc """
  Adds or update a grant on an Acl.

  Takes five parameters:
  - `subject_id`: who we are granting access to
  - `acl_id`: what ACL we're applying a grant to
  - `verb`: which verb/action
  - `value`: true, false, or nil
  - `opts`: additional options

  ## Examples

      iex> Bonfire.Boundaries.Grants.grant("subject_123", "acl_456", :read, true)
  """
  def grant(subject_id, acl_id, verb, value, opts \\ [])

  # TODO: optimise?
  def grant(subject_ids, acl_id, verb, value, opts) when is_list(subject_ids),
    do:
      subject_ids
      |> Circles.circle_ids()
      |> Enum.map(&grant(&1, acl_id, verb, value, opts))

  # TODO: optimise?
  def grant(subject_id, acl_id, verbs, value, opts) when is_list(verbs),
    do: Enum.map(verbs, &grant(subject_id, acl_id, &1, value, opts))

  def grant(subject_id, acl_id, verb, value, opts)
      when is_atom(verb) and not is_nil(verb) do
    debug(verb, "lookup verb")

    verb_id =
      Bonfire.Boundaries.Verbs.get!(verb)[:id]
      |> debug

    grant(subject_id, acl_id, verb_id, value, opts)
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

  @doc """
  Edits or adds grants to an ACL based on a role.

  ## Examples

      iex> Bonfire.Boundaries.Grants.grant_role("subject_123", "acl_456", :admin, [])
      {:ok, %Grant{}}
  """
  def grant_role(subject, acl_id, role, opts \\ [])

  def grant_role(subjects, acl_id, role, opts) when is_list(subjects) do
    Enum.flat_map(subjects, &grant_role(&1, acl_id, role, opts))
  end

  def grant_role(subject_id, acl_id, role, opts) do
    debug(opts, "opts")

    with {:ok, can_verbs, cannot_verbs} <- Roles.verbs_for_role(role, opts) do
      debug(can_verbs, "grant true for verbs")
      debug(cannot_verbs, "grant false for verbs")

      # first remove existing grants to this subject
      # FIXME: what if the user granted a separate role or custom verbs to the same subject? we should only remove grants that match the old role we're changing (if any)
      remove_subject_from_acl(subject_id, acl_id)
      |> debug("cleeen before granting #{role}")

      # then re-add based on role
      # TODO: optimise with an insert_all or single changeset?
      grant(subject_id, acl_id, can_verbs, true, opts) ++
        grant(subject_id, acl_id, cannot_verbs, false, opts)
    else
      {:error, e} ->
        raise e

      e ->
        error(e, "No such role found")
        raise "No such role found"
    end
  end

  @doc """
  Removes a subject's grants from an ACL or ACLs.

  ## Examples

      iex> Bonfire.Boundaries.Grants.remove_subject_from_acl("subject_123", ["acl_456", "acl_789"])
      {:ok, %{}}
  """
  def remove_subject_from_acl(_subject, acls)
      when is_nil(acls) or (is_list(acls) and length(acls) == 0),
      do: error("No boundary ID provided, so could not remove.")

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
    |> proload(:named)
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
  defp list_my_q(%{id: user_id} = user) do
    list_q(user)
    |> join(:inner, [grant: grant], caretaker in assoc(grant, :caretaker), as: :caretaker)
    |> where([caretaker: caretaker], caretaker.caretaker_id == ^user_id)
  end

  @doc """
    Lists the grants for a given ACL.
  """
  def list_for_acl(acl, opts), do: repo().many(list_for_acl_q(acl, opts))

  defp list_for_acl_q(acl, opts) do
    list_q(opts)
    |> where([grant: grant], grant.acl_id in ^ulids(acl))
  end

  @doc """
    Returns the subject(s) from a list of grants.
  """
  def subjects(grants) when is_list(grants) and length(grants) > 0 do
    Enum.reduce(grants, [], fn grant, subjects_acc ->
      subjects_acc ++ [grant.subject]
    end)
    |> Enum.uniq()
  end

  def subjects(_), do: %{}

  @doc """
    Returns a list of grants-per-subject from a list of grants.
  """
  def subject_grants(grants) when is_list(grants) and length(grants) > 0 do
    # TODO: rewrite this whole thing tbh
    Enum.reduce(grants, %{}, fn grant, subjects_acc ->
      new_grant = [Map.drop(grant, [:subject])]
      new_subject = %{subject: grant.subject, grants: new_grant}

      Map.update(
        subjects_acc,
        # key
        grant.subject_id,
        # first entry
        new_subject,
        fn existing_subject ->
          Map.update(
            existing_subject,
            # key
            :grants,
            # first entry
            new_grant,
            fn existing_grants ->
              existing_grants ++ new_grant
            end
          )
        end
      )
    end)

    # |> debug
  end

  def subject_grants(_), do: %{}

  @doc """
  Returns a list of grants-per-verb-per-subject from a list of grants.

  ## Examples

      iex> Bonfire.Boundaries.Grants.subject_verb_grants([%Grant{}])
      %{}
  """
  def subject_verb_grants(grants) when is_list(grants) and length(grants) > 0 do
    # TODO: rewrite this whole thing tbh
    Enum.reduce(grants, %{}, fn grant, subjects_acc ->
      new_grant = %{grant.verb_id => Map.drop(grant, [:subject])}
      new_subject = %{subject: grant.subject, grants: new_grant}

      Map.update(
        subjects_acc,
        # key
        grant.subject_id,
        # first entry
        new_subject,
        fn existing_subject ->
          Map.update(
            existing_subject,
            # key
            :grants,
            # first entry
            new_grant,
            fn existing_grants ->
              Map.merge(existing_grants, new_grant)
            end
          )
        end
      )
    end)

    # |> debug
  end

  def subject_verb_grants(_), do: %{}

  @doc """
  Returns a list of grants-per-subject-per-verb from a list of grants.

  ## Examples

      iex> Bonfire.Boundaries.Grants.verb_subject_grant([%Grant{}])
      %{}
  """
  def verb_subject_grant(grants) when is_list(grants) and length(grants) > 0 do
    # TODO: rewrite this whole thing tbh
    Enum.reduce(grants, %{}, fn grant, verbs_acc ->
      new_grant = %{grant.subject_id => Map.drop(grant, [:verb])}
      new_verb = %{verb: grant.verb, subject_verb_grants: new_grant}

      Map.update(
        verbs_acc,
        # key
        grant.verb_id,
        # first entry
        new_verb,
        fn existing_verb ->
          Map.update(
            existing_verb,
            # key
            :subject_verb_grants,
            # first entry
            new_grant,
            fn existing_grants ->
              Map.merge(existing_grants, new_grant)
            end
          )
        end
      )
    end)

    # |> debug
  end

  def verb_subject_grant(_), do: %{}

  @doc """
  Converts a list of grants to a list of tuples for a given creator.

  ## Examples

      iex> Bonfire.Boundaries.Grants.grants_to_tuples(%User{}, %{grants: [%Grant{}]})
      [{%User{}, :some_role}]
  """
  def grants_to_tuples(creator, %{grants: grants}), do: grants_to_tuples(creator, grants)

  def grants_to_tuples(creator, grants) when is_list(grants) do
    grants
    # |> repo().maybe_preload(:subject)
    |> repo().maybe_preload(subject: [:named, stereotyped: [:named]])
    |> repo().maybe_preload(subject: [:profile, :character])
    |> debug()
    |> subject_grants()
    |> Enum.map(fn
      {_subject_id, %{subject: subject, grants: grants}} ->
        # TODO: compute positive/negative permissions?
        {subject, Roles.role_from_grants(grants, current_user: creator)}
    end)
  end
end
