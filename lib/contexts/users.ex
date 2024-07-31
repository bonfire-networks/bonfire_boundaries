defmodule Bonfire.Boundaries.Users do
  @moduledoc """
  Reads fixtures in configuration and creates a default boundaries setup for a user
  """

  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
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
    %{
      acls: _acls,
      circles: _circles,
      grants: grants,
      named: named,
      controlleds: controlleds,
      stereotypes: stereotypes
    } =
      params =
      prepare_default_boundaries(
        user,
        default_profile_visibility(opts[:undiscoverable]) ++
          maybe_request_before_follow(opts[:request_before_follow]),
        opts
      )
      |> debug()

    # first acls and circles
    do_insert_main(user, params)

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
  Creates any missing boundaries for an existing user. Used when the app or config has defined some new types of default boundaries.

  ## Parameters
    - `user`: The user for whom to create the missing boundaries.
    - `opts`: Optional parameters for customizing the boundaries (not currently used)

  ## Examples

      > Bonfire.Boundaries.Users.create_missing_boundaries(user)
  """
  def create_missing_boundaries(user, opts \\ []) do
    %{
      acls: acls,
      circles: circles,
      grants: grants,
      named: named,
      controlleds: controlleds,
      stereotypes: stereotypes
    } = prepare_default_boundaries(user, [], opts)

    # do not attempt re-creating any existing stereotypes...

    existing_stereotypes =
      stereotypes
      |> Enum.map(&e(&1, :stereotype_id, nil))
      |> debug("all stereos")
      |> Boundaries.find_caretaker_stereotypes(user, ...)
      |> Enum.map(&e(&1, :stereotyped, :stereotype_id, nil))
      |> debug("existing stereos")

    stereotypes =
      stereotypes
      |> Enum.reject(&(e(&1, :stereotype_id, nil) in existing_stereotypes))
      |> debug("new stereos")

    acls =
      acls
      |> Enum.reject(&(e(&1, :stereotype_id, nil) in existing_stereotypes))
      |> debug("missing acls")

    circles =
      circles
      |> Enum.reject(&(e(&1, :stereotype_id, nil) in existing_stereotypes))
      |> debug("missing circles")

    # first acls and circles
    do_insert_main(user, %{acls: acls, circles: circles, stereotypes: stereotypes})

    repo().insert_or_ignore(Stereotyped, stereotypes)

    # Then grants
    # TODO: can we avoid attempting to re-insert existing grants
    repo().insert_or_ignore(Grant, grants)
    # Then the mixins
    repo().insert_or_ignore(Named, named)
    repo().insert_or_ignore(Controlled, controlleds)
    # NOTE: The ACLs and Circles must be deleted when the user is deleted.
    # Grants will take care of themselves because they have a strong pointer acl_id.
  end

  defp prepare_circles(user_default_boundaries) do
    for {k, v} <- Map.fetch!(user_default_boundaries, :circles), into: %{} do
      {k,
       v
       |> Map.put(:id, ULID.generate())
       |> stereotype(Circles)}
    end
  end

  defp prepare_acls(user_default_boundaries) do
    for {k, v} <- Map.fetch!(user_default_boundaries, :acls), into: %{} do
      {k,
       v
       |> Map.put(:id, ULID.generate())
       |> stereotype(Acls)}
    end
  end

  defp format_verb(verb) when is_atom(verb), do: %{verb_id: Verbs.get_id!(verb), value: true}
  defp format_verb(verb) when is_binary(verb), do: %{verb_id: verb, value: true}

  defp format_verb({verb, v}) when is_atom(verb) and is_boolean(v),
    do: %{verb_id: Verbs.get_id!(verb), value: v}

  defp format_verb({verb, v}) when is_binary(verb) and is_boolean(v),
    do: %{verb_id: verb, value: v}

  defp prepare_grants(user_default_boundaries, acls, circles, user) do
    for {acl, entries} <- Map.fetch!(user_default_boundaries, :grants),
        {circle, verbs} <- entries,
        verb <- verbs do
      format_verb(verb)
      |> Map.merge(%{
        id: ULID.generate(),
        acl_id: default_acl_id(acls, acl),
        subject_id: default_subject_id(circles, user, circle)
      })
    end
  end

  defp prepare_controlleds(user_default_boundaries, acls, acls_extra, user) do
    for {:SELF, acls_default} <- Map.fetch!(user_default_boundaries, :controlleds),
        ### control access to the user themselves (e.g. to view their profile or mention them)
        acl <- acls_default ++ acls_extra do
      %{id: user.id, acl_id: default_acl_id(acls, acl)}
    end
  end

  defp prepare_nameds(nameds) do
    nameds
    |> Enum.filter(& &1[:name])
    |> Enum.map(&Map.take(&1, [:id, :name]))
  end

  defp prepare_stereotypes(stereotypes) do
    stereotypes
    |> Enum.filter(& &1[:stereotype_id])
    |> Enum.map(&Map.take(&1, [:id, :stereotype_id]))
  end

  defp prepare_default_boundaries(user, acls_extra, _opts) do
    # debug(opts)
    user_default_boundaries = Boundaries.user_default_boundaries()
    #  |> debug("create_default_boundaries")
    circles = prepare_circles(user_default_boundaries)
    acls = prepare_acls(user_default_boundaries)

    grants = prepare_grants(user_default_boundaries, acls, circles, user)

    controlleds = prepare_controlleds(user_default_boundaries, acls, acls_extra, user)

    # |> info("circles for #{e(user, :character, :username, nil)}")
    circles_values = Map.values(circles)
    # |> info("acls for #{e(user, :character, :username, nil)}")
    acls_values = Map.values(acls)

    named = prepare_nameds(acls_values ++ circles_values)
    stereotypes = prepare_stereotypes(acls_values ++ circles_values)

    %{
      acls: acls_values,
      circles: circles_values,
      grants: grants,
      named: named,
      controlleds: controlleds,
      stereotypes: stereotypes
    }
  end

  defp do_insert_main(user, %{acls: acls, circles: circles, stereotypes: _stereotypes}) do
    repo().insert_all_or_ignore(Acl, Enum.map(acls, &Map.take(&1, [:id])))
    repo().insert_all_or_ignore(Circle, Enum.map(circles, &Map.take(&1, [:id])))
    # repo().insert_all_or_ignore(Stereotyped, stereotypes)
    Boundaries.take_care_of!(acls ++ circles, user)
  end

  defp default_profile_visibility(bool) do
    if !bool and
         !Bonfire.Common.Config.get(
           [Bonfire.Me.Users, :undiscoverable],
           false
         ) do
      [:guests_may_see_read]
    else
      [:guests_may_read]
    end
  end

  defp maybe_request_before_follow(bool) do
    if bool || Bonfire.Common.Config.get([Bonfire.Me.Users, :request_before_follow]) do
      [:no_follow]
    else
      []
    end
  end

  # support for create_default_boundaries/1
  defp stereotype(attrs, module) do
    case attrs[:stereotype] do
      nil ->
        attrs

      other ->
        attrs
        |> Map.put(:stereotype_id, module.get_id!(other))
        |> Map.delete(:stereotype)
    end
  end

  # support for create_default_boundaries/1
  defp default_acl_id(acls, acl_id) do
    with nil <- Map.get(acls, acl_id, %{})[:id],
         nil <- Acls.get_id(acl_id) do
      raise RuntimeError,
        message: "invalid acl given in new user boundaries config: #{inspect(acl_id)}"
    end
  end

  # support for create_default_boundaries/1
  defp default_subject_id(_circles, user, :SELF), do: user.id

  defp default_subject_id(circles, _user, circle_id) do
    with nil <- Map.get(circles, circle_id, %{})[:id],
         nil <- Circles.get_id(circle_id) do
      raise RuntimeError,
        message: "invalid circle given in new user boundaries config: #{inspect(circle_id)}"
    end
  end
end
