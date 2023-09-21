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
  alias Pointers.ULID

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

  def prepare_default_boundaries(user, acls_extra, _opts) do
    # debug(opts)

    user_default_boundaries = Boundaries.user_default_boundaries()
    #  |> debug("create_default_boundaries")
    circles =
      for {k, v} <- Map.fetch!(user_default_boundaries, :circles), into: %{} do
        {k,
         v
         |> Map.put(:id, ULID.generate())
         |> stereotype(Circles)}
      end

    acls =
      for {k, v} <- Map.fetch!(user_default_boundaries, :acls), into: %{} do
        {k,
         v
         |> Map.put(:id, ULID.generate())
         |> stereotype(Acls)}
      end

    grants =
      for {acl, entries} <- Map.fetch!(user_default_boundaries, :grants),
          {circle, verbs} <- entries,
          verb <- verbs do
        case verb do
          _ when is_atom(verb) ->
            %{verb_id: Verbs.get_id!(verb), value: true}

          _ when is_binary(verb) ->
            %{verb_id: verb, value: true}

          {verb, v} when is_atom(verb) and is_boolean(v) ->
            %{verb_id: Verbs.get_id!(verb), value: v}

          {verb, v} when is_binary(verb) and is_boolean(v) ->
            %{verb_id: verb, value: v}
        end
        |> Map.merge(%{
          id: ULID.generate(),
          acl_id: default_acl_id(acls, acl),
          subject_id: default_subject_id(circles, user, circle)
        })
      end

    ### control access to the user themselves (e.g. to view their profile or mention them)
    controlleds =
      for {:SELF, acls_default} <- Map.fetch!(user_default_boundaries, :controlleds),
          acl <- acls_default ++ acls_extra do
        %{id: user.id, acl_id: default_acl_id(acls, acl)}
      end

    # |> info("circles for #{e(user, :character, :username, nil)}")
    circles = Map.values(circles)

    # |> info("acls for #{e(user, :character, :username, nil)}")
    acls = Map.values(acls)

    named =
      (acls ++ circles)
      |> Enum.filter(& &1[:name])
      |> Enum.map(&Map.take(&1, [:id, :name]))

    stereotypes =
      (acls ++ circles)
      |> Enum.filter(& &1[:stereotype_id])
      |> Enum.map(&Map.take(&1, [:id, :stereotype_id]))

    %{
      acls: acls,
      circles: circles,
      grants: grants,
      named: named,
      controlleds: controlleds,
      stereotypes: stereotypes
    }
  end

  def do_insert_main(user, %{acls: acls, circles: circles, stereotypes: _stereotypes}) do
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
