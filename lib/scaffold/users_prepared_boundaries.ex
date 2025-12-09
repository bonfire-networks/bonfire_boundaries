defmodule Bonfire.Boundaries.Scaffold.Users.PreparedBoundaries do
  @moduledoc """
  This module structures the information about the default boundaries for a newly created user before they are inserted in the database.
  It takes care of reading the configuration about the default boundaries and prepare the information for the  Bonfire.Boundaries.Scaffold.Users module.
  """
  use Bonfire.Common.Config
  import Untangle

  alias __MODULE__
  alias Bonfire.Common.Types
  alias Needle.ULID

  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.Scaffold.Users.PreparedBoundaries
  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Verbs

  alias Bonfire.Data.Identity.Named
  alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.AccessControl.Controlled
  alias Bonfire.Data.AccessControl.Circle
  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.AccessControl.Stereotyped

  defstruct acls: [],
            circles: [],
            grants: [],
            named: [],
            controlleds: [],
            stereotypes: []

  @doc """
  Creates PreparedBoundaries for a given user based on the runtime config.
  """
  def from_config(user, opts \\ []) do
    # TODO: document what this is and find a better variable name
    acls_extra =
      if not is_list(opts) or opts[:skip_extra_acls] do
        []
      else
        default_profile_visibility(opts[:undiscoverable]) ++
          maybe_request_before_follow(opts[:request_before_follow])
      end

    prepare_boundaries(user, acls_extra, opts)
    |> debug("prepared boundaries for user")
  end

  defp prepare_boundaries(user, acls_extra, opts) do
    user_default_boundaries =
      Boundaries.user_default_boundaries(!(opts == :remote or opts[:local] == false))

    # |> debug("user_default_boundaries")

    circles = prepare_circles(user_default_boundaries)
    acls = prepare_acls(user_default_boundaries)

    grants = prepare_grants(user_default_boundaries, acls, circles, user, opts)

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

  defp prepare_circles(user_default_boundaries) do
    for {k, v} <- Map.fetch!(user_default_boundaries, :circles), into: %{} do
      {k,
       v
       |> Map.put(:id, Needle.UID.generate(Circle))
       |> stereotype(Circles)}
    end
  end

  defp prepare_acls(user_default_boundaries) do
    for {k, v} <- Map.fetch!(user_default_boundaries, :acls), into: %{} do
      {k,
       v
       |> Map.put(:id, Needle.UID.generate(Acl))
       |> stereotype(Acls)}
    end
  end

  defp format_verb(verb) when is_atom(verb), do: %{verb_id: Verbs.get_id!(verb), value: true}
  defp format_verb(verb) when is_binary(verb), do: %{verb_id: verb, value: true}

  defp format_verb({verb, v}) when is_atom(verb) and is_boolean(v),
    do: %{verb_id: Verbs.get_id!(verb), value: v}

  defp format_verb({verb, v}) when is_binary(verb) and is_boolean(v),
    do: %{verb_id: verb, value: v}

  defp prepare_grants(user_default_boundaries, acls, circles, user, opts) do
    for {acl, entries} <- Map.fetch!(user_default_boundaries, :grants),
        {circle, verbs} <- entries,
        verb <- verbs do
      format_verb(verb)
      |> Map.merge(%{
        id: Needle.UID.generate(Grant),
        acl_id: default_acl_id(acls, acl),
        subject_id: default_subject_id(circles, user, circle, opts)
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
      [:everyone_may_see_read]
    else
      [:everyone_may_read]
    end
  end

  defp maybe_request_before_follow(bool) do
    if bool || Bonfire.Common.Config.get([Bonfire.Me.Users, :request_before_follow]) do
      [:no_follow]
    else
      []
    end
  end

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

  defp default_acl_id(acls, acl_id) do
    with nil <- Map.get(acls, acl_id, %{})[:id],
         nil <- Acls.get_id(acl_id) do
      raise RuntimeError,
        message: "invalid acl given in new user boundaries config: #{inspect(acl_id)}"
    end
  end

  defp default_subject_id(_circles, user, :SELF, _opts), do: user.id

  defp default_subject_id(circles, _user, circle_slug, opts) do
    with nil <- Map.get(circles, circle_slug, %{})[:id],
         nil <- Circles.get_id(circle_slug),
         false <- (is_list(opts) and Types.uid(opts[:custom_circles][circle_slug])) || false do
      raise RuntimeError,
        message: "invalid circle given in new user boundaries config: #{inspect(circle_slug)}"
    end
  end
end
