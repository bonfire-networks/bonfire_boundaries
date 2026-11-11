defmodule Bonfire.Boundaries.Scaffold.Users do
  @moduledoc """
  Reads fixtures in configuration and creates a default boundaries setup for a user
  """

  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  require Ecto.Query
  alias Bonfire.Boundaries.Scaffold.Users.PreparedBoundaries
  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Grants
  alias Bonfire.Data.AccessControl.Stereotyped
  alias Bonfire.Boundaries.Verbs

  alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.AccessControl.Controlled
  alias Bonfire.Data.AccessControl.Circle
  alias Bonfire.Data.AccessControl.Grant

  alias Bonfire.Data.Identity.Named
  alias Needle.ULID

  @doc """
  Creates the default boundaries setup for a newly-created user.

  ## Parameters
    - `user`: The user for whom to create the default boundaries.
    - `opts`: Optional parameters for customizing the boundaries (such as whether the user is `undiscoverable` or requires `request_before_follow`)

  ## Examples

      > Bonfire.Boundaries.Scaffold.Users.create_default_boundaries(user)
  """
  def create_default_boundaries(user, opts \\ []) do
    PreparedBoundaries.from_config(
      user,
      opts
    )
    |> insert_prepared_boundaries(user)
  end

  @doc """
  Sets whether following `user` needs their approval, on a user that already exists: `true` withholds the `everyone_may_follow` grant (leaving the ask to `everyone_may_request`), `false` gives it back. The same rule `create_default_boundaries/2` applies at creation with `request_before_follow`, for an account whose choice changes later (eg. a remote person who starts, or stops, approving followers by hand). Idempotent.

  ## Examples

      > Bonfire.Boundaries.Scaffold.Users.set_request_before_follow(user, true)
  """
  def set_request_before_follow(user, true) do
    acl_id = Acls.get_id!(:everyone_may_follow)

    repo().delete_all(
      Ecto.Query.from(c in Controlled, where: c.id == ^id(user) and c.acl_id == ^acl_id)
    )
  end

  def set_request_before_follow(user, false) do
    repo().insert_all_or_ignore(Controlled, [
      %{id: id(user), acl_id: Acls.get_id!(:everyone_may_follow)}
    ])
  end

  defp insert_prepared_boundaries(
         %PreparedBoundaries{
           acls: acls,
           circles: circles,
           grants: grants,
           named: named,
           controlleds: controlleds,
           stereotypes: stereotypes
         } = config,
         user
       ) do
    debug(config, "inserting prepared boundaries for user #{id(user)}")

    # first acls and circles
    insert_acls(user, acls)
    insert_circles(user, circles)

    add_caretaker(acls ++ circles, user)
    repo().insert_all_or_ignore(Stereotyped, stereotypes)

    # Then grants
    deduped_grants = Grants.uniq_grants_to_create(grants)
    repo().insert_all_or_ignore(Grant, deduped_grants)

    # Then the mixins
    repo().insert_all_or_ignore(Named, named)
    repo().insert_all_or_ignore(Controlled, controlleds)
    # NOTE: The ACLs and Circles must be deleted when the user is deleted.
    # Grants will take care of themselves because they have a strong pointer acl_id.
  end

  @doc """
  Removes from the list stereotypes already present in the database
  """
  # the caretaker's circles and ACLs that already exist, as `%{stereotype_id => id}`
  defp existing_stereotype_ids(stereotypes, user) do
    stereotypes
    |> Enum.map(&e(&1, :stereotype_id, nil))
    |> debug("all stereos")
    |> Boundaries.find_caretaker_stereotypes(user, ...)
    |> Map.new(&{e(&1, :stereotyped, :stereotype_id, nil), &1.id})
    |> debug("existing stereos")
  end

  @doc """
  Creates any missing boundaries for an existing user. Used when the app or config has defined some new types of default boundaries.

  ## Parameters
    - `user`: The user for whom to create the missing boundaries.
    - `opts`: Optional parameters for customizing the boundaries (not currently used)

  ## Examples

      > Bonfire.Boundaries.Scaffold.Users.create_missing_boundaries(user)
  """
  def create_missing_boundaries(user, opts \\ []) do
    %PreparedBoundaries{
      acls: acls,
      circles: circles,
      grants: grants,
      named: named,
      controlleds: controlleds,
      stereotypes: stereotypes
    } = PreparedBoundaries.from_config(user, Keyword.put(opts, :skip_extra_acls, true))

    existing = existing_stereotype_ids(stereotypes, user)

    # the config's rows come with fresh ids, so whatever the caretaker has already is pointed at instead: a new ACL's grants then apply to the circle the caretaker's blocked people are already in, rather than to a duplicate of it
    existing_ids =
      for %{id: new_id, stereotype_id: stereotype_id} <- stereotypes,
          existing_id = existing[stereotype_id],
          into: %{},
          do: {new_id, existing_id}

    to_existing = &Map.get(existing_ids, &1, &1)

    missing_stereotypes =
      stereotypes
      |> Enum.reject(&Map.has_key?(existing, &1.stereotype_id))
      |> debug("new stereos")

    missing_ids = MapSet.new(missing_stereotypes, & &1.id)

    missing_acls =
      acls
      |> Enum.filter(&MapSet.member?(missing_ids, &1.id))
      |> debug("missing acls")

    missing_circles =
      circles
      |> Enum.filter(&MapSet.member?(missing_ids, &1.id))
      |> debug("missing circles")

    # every grant the config asks for, on the rows as they now are: one already there is skipped by the unique index on `[:acl_id, :subject_id, :verb_id]`, so this also restores grants missing from an ACL that exists
    missing_grants =
      grants
      |> Enum.map(
        &%{&1 | acl_id: to_existing.(&1.acl_id), subject_id: to_existing.(&1.subject_id)}
      )
      |> debug("missing grants")

    insert_prepared_boundaries(
      %PreparedBoundaries{
        acls: missing_acls,
        circles: missing_circles,
        grants: missing_grants,
        named: Enum.filter(named, &MapSet.member?(missing_ids, &1.id)),
        controlleds: Enum.map(controlleds, &Map.update!(&1, :acl_id, to_existing)),
        stereotypes: missing_stereotypes
      },
      user
    )

    missing_acls
  end

  defp add_caretaker(objects, user),
    do: Boundaries.take_care_of!(objects, user)

  defp insert_acls(user, acls) do
    repo().insert_all_or_ignore(Acl, Enum.map(acls, &Map.take(&1, [:id])))
  end

  defp insert_circles(user, circles) do
    repo().insert_all_or_ignore(Circle, Enum.map(circles, &Map.take(&1, [:id])))
  end
end
