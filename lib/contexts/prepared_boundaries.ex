defmodule Bonfire.Boundaries.Users.PreparedBoundaries do
  @moduledoc """
  This module structures the information about the default boundaries for a newly created user before they are inserted in the database.
  It takes care of reading the configuration about the default boundaries and prepare the information for the  Bonfire.Boundaries.Users module.
  """
  alias __MODULE__
  alias Bonfire.Boundaries

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

  defstruct acls: [],
            circles: [],
            grants: [],
            named: [],
            controlleds: [],
            stereotypes: []

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

  @doc """
  Creates PreparedBoundaries for a given user based on the runtime config.
  """
  def from_config(user, opts, skip_acls_extra \\ false)

  def from_config(user, opts, false = _skip_acls_extra) do
    # TODO: document what this is and find a better variable name
    acls_extra =
      default_profile_visibility(opts[:undiscoverable]) ++
        maybe_request_before_follow(opts[:request_before_follow])

    prepare_boundaries(user, acls_extra, opts)
  end

  def from_config(user, opts, true = _skip_acls_extra) do
    # TODO: document what this is and find a better variable name
    prepare_boundaries(user, [], opts)
  end

  defp prepare_boundaries(user, acls_extra, opts) do
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

    %PreparedBoundaries{
      acls: acls_values,
      circles: circles_values,
      grants: grants,
      named: named,
      controlleds: controlleds,
      stereotypes: stereotypes
    }
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
