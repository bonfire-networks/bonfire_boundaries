defmodule Bonfire.Boundaries.GrantsRemoveTest do
  @moduledoc """
  Covers removing grants (`Grants.remove_role/4`, and `Grants.grant/5` with a nil value). Removing is one delete query, so two processes removing the same grant at once both succeed: the one that finds no row left gets `{:ok, 0}` rather than a crash.
  """
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries.Grants
  alias Bonfire.Boundaries.Roles

  setup do
    me = Bonfire.Me.Fake.fake_user!()
    someone = Bonfire.Me.Fake.fake_user!()
    {:ok, acl} = Bonfire.Boundaries.Acls.simple_create(me, "a preset")
    {:ok, me: me, someone: someone, acl: acl}
  end

  defp stored(acl, me) do
    Grants.list_for_acl(acl.id, current_user: me, skip_boundary_check: true)
    |> Enum.map(&{&1.verb_id, &1.value})
    |> Enum.sort()
  end

  describe "removing a role" do
    test "deletes its grants", %{me: me, someone: someone, acl: acl} do
      {:ok, can, _} = Roles.verbs_for_role("read", [])
      Grants.grant_role(someone.id, acl.id, "read", current_user: me)

      # the positive first: the role's grants are stored
      assert length(stored(acl, me)) == length(can)

      results = Grants.remove_role(someone.id, acl.id, "read", current_user: me)

      assert results != [] and Enum.all?(results, &(&1 == {:ok, 1})),
             "expected one row deleted per verb, got: #{inspect(results)}"

      assert stored(acl, me) == []
    end

    test "a second time, with its grants already gone, does not crash", %{
      me: me,
      someone: someone,
      acl: acl
    } do
      Grants.grant_role(someone.id, acl.id, "read", current_user: me)
      Grants.remove_role(someone.id, acl.id, "read", current_user: me)

      # the state a process sees when another one removed the same role just before it
      results = Grants.remove_role(someone.id, acl.id, "read", current_user: me)

      assert results != [] and Enum.all?(results, &(&1 == {:ok, 0})),
             "expected no rows deleted, got: #{inspect(results)}"
    end

    test "keeps a grant of the opposite value on the same verb", %{
      me: me,
      someone: someone,
      acl: acl
    } do
      Grants.grant_role(someone.id, acl.id, "cannot_read", current_user: me)
      before = stored(acl, me)
      assert before != []

      results = Grants.remove_role(someone.id, acl.id, "read", current_user: me)

      assert Enum.all?(results, &(&1 == {:ok, 0})),
             "expected no rows deleted, got: #{inspect(results)}"

      assert stored(acl, me) == before
    end
  end

  describe "setting a grant to nil" do
    test "deletes it", %{me: me, someone: someone, acl: acl} do
      assert {:ok, _} = Grants.grant(someone.id, acl.id, :read, true, current_user: me)
      assert [_] = stored(acl, me)

      assert Grants.grant(someone.id, acl.id, :read, nil, current_user: me) == {:ok, 1}
      assert stored(acl, me) == []
    end

    test "with no grant stored, does not crash", %{me: me, someone: someone, acl: acl} do
      assert Grants.grant(someone.id, acl.id, :read, nil, current_user: me) == {:ok, 0}
    end
  end
end
