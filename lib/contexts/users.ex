defmodule Bonfire.Boundaries.Users do
  @moduledoc """
  Reads fixtures in configuration and creates a default boundaries setup for a user
  """

  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.Users.PreparedBoundaries
  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Circles
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

      > Bonfire.Boundaries.Users.create_default_boundaries(user)
  """
  def create_default_boundaries(user, opts \\ []) do
    PreparedBoundaries.from_config(
      user,
      opts
    )
    |> insert_prepared_boundaries(user)
  end

  defp insert_prepared_boundaries(
         %PreparedBoundaries{
           acls: acls,
           circles: circles,
           grants: grants,
           named: named,
           controlleds: controlleds,
           stereotypes: stereotypes
         },
         user
       ) do
    # first acls and circles
    insert_acls(user, acls)
    insert_circles(user, circles)

    add_caretaker(acls ++ circles, user)
    repo().insert_all_or_ignore(Stereotyped, stereotypes)

    # Then grants
    repo().insert_all_or_ignore(Grant, grants)
    # Then the mixins
    repo().insert_all_or_ignore(Named, named)
    repo().insert_all_or_ignore(Controlled, controlleds)
    # NOTE: The ACLs and Circles must be deleted when the user is deleted.
    # Grants will take care of themselves because they have a strong pointer acl_id.
  end

  @doc """
  Removes from the list stereotypes already present in the database
  """
  defp reject_existing_stereotypes(stereotypes, user) do
    existing_stereotypes =
      stereotypes
      |> Enum.map(&e(&1, :stereotype_id, nil))
      |> debug("all stereos")
      |> Boundaries.find_caretaker_stereotypes(user, ...)
      |> Enum.map(&e(&1, :stereotyped, :stereotype_id, nil))
      |> debug("existing stereos")

    stereotypes
    |> Enum.reject(&(e(&1, :stereotype_id, nil) in existing_stereotypes))
    |> debug("new stereos")
  end

  @doc """
  Creates any missing boundaries for an existing user. Used when the app or config has defined some new types of default boundaries.

  ## Parameters
    - `user`: The user for whom to create the missing boundaries.
    - `opts`: Optional parameters for customizing the boundaries (not currently used)

  ## Examples

      > Bonfire.Boundaries.Users.create_missing_boundaries(user)
  """
  def create_missing_boundaries(user) do
    %PreparedBoundaries{
      acls: acls,
      circles: circles,
      grants: grants,
      named: named,
      controlleds: controlleds,
      stereotypes: stereotypes
    } = PreparedBoundaries.from_config(user, [])

    missing_stereotypes = stereotypes |> reject_existing_stereotypes(user)
    missing_stereotypes_ids = stereotypes |> Enum.map(& &1.stereotype_id)

    missing_acls =
      acls
      |> Enum.filter(&(e(&1, :stereotype_id, nil) in missing_stereotypes_ids))
      |> debug("missing acls")

    missing_circles =
      circles
      |> Enum.filter(&(e(&1, :stereotype_id, nil) in missing_stereotypes_ids))
      |> debug("missing circles")

    missing_acl_ids = missing_acls |> Enum.map(& &1.id)

    missing_grants =
      grants
      |> Enum.filter(&(e(&1, :acl_id, nil) in missing_acl_ids))
      |> debug("missing grants")

    insert_prepared_boundaries(
      %PreparedBoundaries{
        acls: missing_acls,
        circles: missing_circles,
        grants: missing_grants,
        named: named,
        controlleds: controlleds,
        stereotypes: missing_stereotypes
      },
      user
    )
  end

  defp add_caretaker(objects, user),
    do: Boundaries.take_care_of!(objects, user)

  defp insert_acls(user, acls) do
    repo().insert_all(Acl, Enum.map(acls, &Map.take(&1, [:id])))
  end

  defp insert_circles(user, circles) do
    repo().insert_all(Circle, Enum.map(circles, &Map.take(&1, [:id])))
  end
end
