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
    %PreparedBoundaries{
      acls: acls,
      circles: circles,
      grants: grants,
      named: named,
      controlleds: controlleds,
      stereotypes: stereotypes
    } =
      prepared_boundaries =
      PreparedBoundaries.from_config(
        user,
        opts
      )
      |> debug()

    # first acls and circles
    do_insert_main(user, prepared_boundaries)
    add_caretaker(prepared_boundaries, user)
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

    # first acls and circles
    do_insert_main(user, %PreparedBoundaries{
      acls: missing_acls,
      circles: missing_circles,
      stereotypes: missing_stereotypes
    })

    repo().insert_or_ignore(Stereotyped, missing_stereotypes)

    # Then grants
    # TODO: can we avoid attempting to re-insert existing grants
    repo().insert_or_ignore(Grant, grants)
    # Then the mixins
    repo().insert_or_ignore(Named, named)
    repo().insert_or_ignore(Controlled, controlleds)
    # NOTE: The ACLs and Circles must be deleted when the user is deleted.
    # Grants will take care of themselves because they have a strong pointer acl_id.
  end

  defp add_caretaker(
         %PreparedBoundaries{acls: acls, circles: circles, stereotypes: _stereotypes},
         user
       ),
       do: Boundaries.take_care_of!(acls ++ circles, user)

  defp do_insert_main(user, %PreparedBoundaries{
         acls: acls,
         circles: circles,
         stereotypes: _stereotypes
       }) do
    repo().insert_all(Acl, acls)
    repo().insert_all(Circle, circles)
    # repo().insert_all_or_ignore(Stereotyped, stereotypes)
  end
end
