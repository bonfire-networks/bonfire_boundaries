defmodule Bonfire.Boundaries.Debug do
  @moduledoc """
  Debug utilities for Bonfire Boundaries.

  This module provides functions to debug and inspect user circles, ACLs, and grants.
  """

  use Arrows
  use Bonfire.Common.E

  # import Untangle
  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.Verbs

  alias Bonfire.Common.Utils
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Circles

  import Bonfire.Boundaries.Integration
  # import Ecto.Query, only: [from: 2]

  @doc """
  Prints debug information about a user's circles.

  ## Examples

      iex> Bonfire.Boundaries.Debug.debug_user_circles(user)
      User: user_id
      +------------+------------+
      | circle_id  | circle_name|
      +------------+------------+
      | circle_1   | Friends    |
      | circle_2   | Family     |
      +------------+------------+

  """
  def debug_user_circles(user) do
    user = repo().preload(user, [encircles: [circle: [:named]]], force: true)
    IO.puts("User: #{user.id}")

    for encircle <- user.encircles do
      %{
        circle_id: encircle.circle_id,
        circle_name: e(encircle.circle, :named, :name, nil)
      }
    end
    |> Scribe.print()
  end

  @doc """
  Prints debug information about a user's ACLs.

  ## Examples

      iex> Bonfire.Boundaries.Debug.debug_user_acls(user)
      user ACLs: user_id
      +--------+----------+-----------+------------+---------------+-----------+
      | acl_id | acl_name | acl_stereo| grant_verb | grant_subject | grant_value |
      +--------+----------+-----------+------------+---------------+-----------+
      | acl_1  | Private  | null      | read       | Friends       | true      |
      | acl_2  | Public   | null      | write      | Everyone      | false     |
      +--------+----------+-----------+------------+---------------+-----------+

      iex> Bonfire.Boundaries.Debug.debug_user_acls(user, "Custom label")
      Custom label user ACLs: user_id
      ...

  """
  def debug_user_acls(user, label \\ "") do
    acls = get_user_acls(user)
    IO.puts("#{label} user ACLs: #{user.id}")
    debug_acls(acls)
  end

  defp get_user_acls(user) do
    Acls.list(current_user: user)
    |> repo().preload([:grants])
  end

  defp debug_acls(acls) do
    for acl <- acls,
        grant <- acl.grants do
      %{
        acl_id: acl.id,
        acl_name:
          e(acl, :named, :name, nil) ||
            "[stereotype] " <> e(acl, :stereotyped, :named, :name, ""),
        acl_stereotype: e(acl, :stereotyped, :stereotype_id, nil),
        grant_verb: Verbs.get!(grant.verb_id).verb,
        grant_subject: Circles.get(grant.subject_id)[:name] || grant.subject_id,
        grant_value: grant.value
      }
    end
    # |> debug
    |> Enum.group_by(&{&1.acl_id, &1.grant_subject, &1.grant_value})
    |> for({_k, [v | _] = vs} <- ...) do
      Map.put(v, :grant_verb, Enum.sort(Enum.map(vs, & &1.grant_verb)))
    end
    |> Scribe.print()
  end

  @doc """
  Prints debug information about an object's ACLs.

  ## Examples

      iex> Bonfire.Boundaries.Debug.debug_object_acls(object)
      Object: object_id
      +--------+----------+-----------+------------+---------------+-----------+
      | acl_id | acl_name | acl_stereo| grant_verb | grant_subject | grant_value |
      +--------+----------+-----------+------------+---------------+-----------+
      | acl_1  | Private  | null      | read       | Friends       | true      |
      | acl_2  | Public   | null      | write      | Everyone      | false     |
      +--------+----------+-----------+------------+---------------+-----------+

  """
  def debug_object_acls(thing) do
    acls = Boundaries.list_object_boundaries(thing)
    IO.puts("Object: #{thing.id}")
    debug_acls(acls)
  end

  @doc """
  Prints debug information about users' grants on specific things.

  ## Examples

      iex> Bonfire.Boundaries.Debug.debug_my_grants_on(users, things)
      +------------+------------+---------+-------+
      | subject_id | object_id  | verbs   | value |
      +------------+------------+---------+-------+
      | user_1     | object_1   | [read]  | true  |
      | user_2     | object_2   | [write] | false |
      +------------+------------+---------+-------+

  """
  def debug_my_grants_on(users, things) do
    Boundaries.users_grants_on(users, things)
    |> Enum.map(&Map.take(&1, [:subject_id, :object_id, :verbs, :value]))
    |> Scribe.print()
  end

  @doc """
  Prints debug information about all grants on specific things.

  ## Examples

      iex> Bonfire.Boundaries.Debug.debug_grants_on(things)
      +------------+------------+---------+-------+
      | subject_id | object_id  | verbs   | value |
      +------------+------------+---------+-------+
      | user_1     | object_1   | [read]  | true  |
      | user_2     | object_2   | [reply] | true |
      | user_2     | object_2   | [edit] | false |
      +------------+------------+---------+-------+

  """
  def debug_grants_on(things) do
    Boundaries.list_grants_on(things)
    |> Enum.map(&Map.take(&1, [:subject_id, :object_id, :verbs, :value]))
    |> Scribe.print()
  end

  @doc """
  Prints debug information about grants on specific things for given verbs.

  ## Examples

      iex> Bonfire.Boundaries.Debug.debug_grants_on(things, [:read, :edit])
      +------------+------------+---------+-------+
      | subject_id | object_id  | verbs   | value |
      +------------+------------+---------+-------+
      | user_1     | object_1   | [read]  | true  |
      | user_2     | object_2   | [edit] | false |
      +------------+------------+---------+-------+

  """
  def debug_grants_on(things, verbs) do
    Boundaries.list_grants_on(things, verbs)
    |> Enum.map(&Map.take(&1, [:subject_id, :object_id, :verbs, :value]))
    |> Scribe.print()
  end
end
