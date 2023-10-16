defmodule Bonfire.Boundaries.Debug do
  use Arrows
  # import Untangle
  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.Verbs

  alias Bonfire.Common.Utils
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Boundaries.Circles

  import Bonfire.Boundaries.Integration
  # import Ecto.Query, only: [from: 2]

  defp get_user_acls(user) do
    Acls.list(current_user: user)
    |> repo().preload([:grants])
  end

  def debug_user_circles(user) do
    user = repo().preload(user, [encircles: [circle: [:named]]], force: true)
    IO.puts("User: #{user.id}")

    for encircle <- user.encircles do
      %{
        circle_id: encircle.circle_id,
        circle_name: Utils.e(encircle.circle, :named, :name, nil)
      }
    end
    |> Scribe.print()
  end

  def debug_user_acls(user, label \\ "") do
    acls = get_user_acls(user)
    IO.puts("#{label} user ACLs: #{user.id}")
    debug_acls(acls)
  end

  defp debug_acls(acls) do
    for acl <- acls,
        grant <- acl.grants do
      %{
        acl_id: acl.id,
        acl_name:
          Utils.e(acl, :named, :name, nil) ||
            "[stereotype] " <> Utils.e(acl, :stereotyped, :named, :name, ""),
        acl_stereotype: Utils.e(acl, :stereotyped, :stereotype_id, nil),
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

  def debug_object_acls(thing) do
    acls = Boundaries.list_object_boundaries(thing)
    IO.puts("Object: #{thing.id}")
    debug_acls(acls)
  end

  def debug_my_grants_on(users, things) do
    Boundaries.users_grants_on(users, things)
    |> Enum.map(&Map.take(&1, [:subject_id, :object_id, :verbs, :value]))
    |> Scribe.print()
  end

  def debug_grants_on(things) do
    Boundaries.list_grants_on(things)
    |> Enum.map(&Map.take(&1, [:subject_id, :object_id, :verbs, :value]))
    |> Scribe.print()
  end

  def debug_grants_on(things, verbs) do
    Boundaries.list_grants_on(things, verbs)
    |> Enum.map(&Map.take(&1, [:subject_id, :object_id, :verbs, :value]))
    |> Scribe.print()
  end
end
