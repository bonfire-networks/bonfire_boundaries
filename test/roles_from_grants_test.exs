defmodule Bonfire.Boundaries.RolesFromGrantsTest do
  @moduledoc """
  Covers `Roles.role_from_grants/2`: grants given as a role read back as that role, and with `fallback_to_list: true`, grants that match no role are listed as "Can %{verb}" / "Cannot %{verb}". The verb sits mid-sentence, so it is lowercase.
  """
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries.Roles
  alias Bonfire.Boundaries.Verbs

  # shaped like the grants `EditAclLive` passes in: a value, a verb id, and the loaded verb
  defp grant(slug, value) do
    %{value: value, verb_id: Verbs.get_id!(slug), verb: %{verb: Verbs.get!(slug)[:verb]}}
  end

  test "only positive grants that match no role are listed as 'Can …'" do
    assert Roles.role_from_grants([grant(:like, true)], fallback_to_list: true) == "Can like"
  end

  test "only negative grants that match no role are listed as 'Cannot …'" do
    assert Roles.role_from_grants([grant(:boost, false)], fallback_to_list: true) ==
             "Cannot boost"
  end

  test "mixed grants are listed with both" do
    assert Roles.role_from_grants([grant(:like, true), grant(:boost, false)],
             fallback_to_list: true
           ) == "Can like ; Cannot boost"
  end

  # a role given with `Grants.grant_role/4` is read back as that role, as customising a boundary from a preset does (`Acls.grant_tuples_from_preset/3`): a `cannot_*` role read back as nothing loses the exclusion it stands for
  describe "a role stored as grants reads back as that role" do
    for role <- ["read", "cannot_read"] do
      test role do
        me = Bonfire.Me.Fake.fake_user!()
        someone = Bonfire.Me.Fake.fake_user!()
        {:ok, acl} = Bonfire.Boundaries.Acls.simple_create(me, "a preset")

        results =
          Bonfire.Boundaries.Grants.grant_role(someone.id, acl.id, unquote(role),
            current_user: me
          )

        assert Enum.all?(results, &match?({:ok, _}, &1)),
               "some grants weren't stored: #{inspect(Enum.reject(results, &match?({:ok, _}, &1)))}"

        grants =
          Bonfire.Boundaries.Grants.list_for_acl(acl.id,
            current_user: me,
            skip_boundary_check: true
          )

        stored = grants |> Enum.map(& &1.verb_id) |> Enum.sort()

        {:ok, can, cannot} = Roles.verbs_for_role(unquote(role), [])
        expected = (can ++ cannot) |> Enum.map(&Verbs.get_id!/1) |> Enum.sort()

        assert Roles.role_from_grants(grants, current_user: me) ==
                 String.to_existing_atom(unquote(role)),
               "stored verbs not in the role: #{inspect(stored -- expected)}; role verbs not stored: #{inspect(expected -- stored)}"
      end
    end
  end
end
