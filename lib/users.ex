defmodule Bonfire.Boundaries.Users do
  @moduledoc """
  Reads fixtures in configuration and creates a default boundaries setup for a user
  """
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.{Acls, Circles, Stereotyped, Verbs}
  alias Bonfire.Data.AccessControl.{Acl, Controlled, Circle, Grant}
  alias Bonfire.Data.Identity.Named
  alias Pointers.ULID

  def create_default_boundaries(user) do
    user_default_boundaries = Boundaries.user_default_boundaries()
    #  |> debug("create_default_boundaries")
    circles = for {k, v} <- Map.fetch!(user_default_boundaries, :circles), into: %{} do
      {k, v
      |> Map.put(:id, ULID.generate())
      |> stereotype(Circles)}
    end
    acls = for {k, v} <- Map.fetch!(user_default_boundaries, :acls), into: %{} do
      {k, v
      |> Map.put(:id, ULID.generate())
      |> stereotype(Acls)}
    end
    grants =
      for {acl, entries}  <- Map.fetch!(user_default_boundaries, :grants),
          {circle, verbs} <- entries,
          verb            <- verbs do
        case verb do
          _ when is_atom(verb)   ->
            %{verb_id: Verbs.get_id!(verb), value: true}
          _ when is_binary(verb) ->
            %{verb_id: verb, value: true}
          {verb, v} when is_atom(verb) and is_boolean(v) ->
            %{verb_id: Verbs.get_id!(verb), value: v}
          {verb, v} when is_binary(verb) and is_boolean(v) ->
            %{verb_id: verb, value: v}
        end
        |> Map.merge(%{
          id:         ULID.generate(),
          acl_id:     default_acl_id(acls, acl),
          subject_id: default_subject_id(circles, user, circle),
        })
      end
    controlleds =
      for {:SELF, acls2}  <- Map.fetch!(user_default_boundaries, :controlleds),
          acl <- acls2 do
        %{id: user.id, acl_id: default_acl_id(acls, acl)}
      end
    circles =
      circles
      # |> info("circles for #{e(user, :character, :username, nil)}")
      |> Map.values()
    acls =
      acls
      # |> info("acls for #{e(user, :character, :username, nil)}")
      |> Map.values()
    named =
      (acls ++ circles)
      |> Enum.filter(&(&1[:name]))
      |> Enum.map(&Map.take(&1, [:id, :name]))
    stereotypes =
      (acls ++ circles)
      |> Enum.filter(&(&1[:stereotype_id]))
      |> Enum.map(&Map.take(&1, [:id, :stereotype_id]))
    # First the pointables
    repo().insert_all_or_ignore(Acl,    Enum.map(acls,    &Map.take(&1, [:id])))
    repo().insert_all_or_ignore(Circle, Enum.map(circles, &Map.take(&1, [:id])))
    repo().insert_all_or_ignore(Grant,  grants)
    # Then the mixins
    repo().insert_all_or_ignore(Named, named)
    repo().insert_all_or_ignore(Controlled, controlleds)
    repo().insert_all_or_ignore(Stereotyped, stereotypes)
    # * The ACLs and Circles must be deleted when the user is deleted.
    # * Grants will take care of themselves because they have a strong pointer acl_id.
    Boundaries.take_care_of!(acls ++ circles, user)
  end

  # support for create_default_boundaries/1
  defp stereotype(attrs, module) do
    case attrs[:stereotype] do
      nil -> attrs
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
