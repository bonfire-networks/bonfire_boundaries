defmodule Bonfire.Boundaries.Debug do
  use Arrows
  # import Where
  alias Bonfire.Boundaries
  alias Bonfire.Boundaries.{Summary, Verbs}
  alias Bonfire.Common.Utils
  alias Bonfire.Boundaries.{Acls, Circles}
  alias Bonfire.Common.Repo
  import Ecto.Query, only: [from: 2]

  defp get_user_acls(user) do
    Acls.list(current_user: user, skip_boundary_check: true)
    |> Repo.preload([:grants])
  end

  def debug_user_circles(user) do
    user = Repo.preload user, [encircles: [circle: [:named]]], force: true
    IO.puts "User: #{user.id}"
    for encircle <- user.encircles do
      %{circle_id: encircle.circle_id,
        circle_name: Utils.e(encircle.circle, :named, :name, nil),
      }
    end
    |> Scribe.print()
  end

  def debug_user_acls(user, label \\ "") do
    acls = get_user_acls(user)
    IO.puts "#{label} user ACLs: #{user.id}"
    debug_acls(acls)
  end

  defp debug_acls(acls) do
    for acl <- acls,
        grant <- acl.grants do
      %{acl_id: acl.id,
        acl_name: Utils.e(acl, :named, :name, nil) || "[stereotype] "<> Utils.e(acl, :stereotyped, :named, :name, ""),
        acl_stereotype: Utils.e(acl, :stereotyped, :stereotype_id, nil),
        grant_verb: Verbs.get!(grant.verb_id).verb,
        grant_subject: Circles.get(grant.subject_id)[:name] || grant.subject_id,
        grant_value: grant.value,
      }
    end
    # |> dump
    |> Enum.group_by(&{&1.acl_id, &1.grant_subject, &1.grant_value})
    |> for({_k, [v|_]=vs} <- ...) do
      Map.put(v, :grant_verb, Enum.sort(Enum.map(vs, &(&1.grant_verb))))
    end
    |> Scribe.print()
  end

  def debug_object_acls(thing) do
    acls = Boundaries.list_object_acls(thing)
    IO.puts "Object: #{thing.id}"
    debug_acls(acls)
  end

  def debug_my_grants_on(user, things) when not is_list(user), do: debug_my_grants_on([user], things)
  def debug_my_grants_on(users, thing) when not is_list(thing), do: debug_my_grants_on(users, [thing])
  def debug_my_grants_on(users, things) do
    from(s in Summary,
      where: s.subject_id in ^Utils.ulid(users),
      where: s.object_id in ^Utils.ulid(things)
    )
    |> Repo.all()
    |> Enum.group_by(&{&1.subject_id, &1.object_id, &1.value})
    |> for({_k, [v|_]=vs} <- ...) do
      Map.put(v, :verbs, Enum.sort(Enum.map(vs, &(Verbs.get!(&1.verb_id).verb))))
    end
    |> Enum.map(&Map.take(&1, [:subject_id, :object_id, :verbs, :value]))
    |> Scribe.print()
  end

end
