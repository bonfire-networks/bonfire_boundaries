defmodule Bonfire.Boundaries.Debug do
  use Arrows
  import Where
  alias Bonfire.Boundaries.Verbs
  alias Bonfire.Common.Utils
  alias Bonfire.Boundaries.{Acls, Circles}
  alias Bonfire.Repo

  defp get_user_acls(user) do
    Acls.list(current_user: user, skip_boundary_check: true)
    |> Repo.preload([:grants])
  end

  defp get_object_acls(object) do
    Repo.preload(object, [controlled: [acl: [:named, :grants, stereotyped: [:named]]]]).controlled
    |> Enum.map(&(&1.acl))
    # |> dump
  end

  def debug_user_circles(user) do
    user = Repo.preload user, [encircles: [circle: [:named]]]
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
    |> for({k, [v|_]=vs} <- ...) do
      Map.put(v, :grant_verb, Enum.sort(Enum.map(vs, &(&1.grant_verb))))
    end
    |> Scribe.print()
  end

  def debug_object_acls(thing) do
    acls = get_object_acls(thing)
    IO.puts "Object: #{thing.id}"
    debug_acls(acls)
  end

end
