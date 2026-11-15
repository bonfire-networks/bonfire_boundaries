defmodule Bonfire.Boundaries.ChecksOnceTest do
  @moduledoc """
  A public writing function checks permission once for a call, and the writes it makes inside go through the unchecked `do_*` ones. Each check costs queries (and `can?` on the instance costs more), so these count the calls to the checks while one call runs, in the calling process (call tracing sends a message to this process for each).

  Also the list form of `Grants.grant_role/4` and `change_role/4`: refused once for all the subjects, not raised from inside the mapping.
  """
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries.{Acls, Controlleds, Grants}

  setup do
    # nothing here federates; publishing otherwise spawns federation tasks with no DB ownership in tests
    Process.put(:federating, false)

    me = Bonfire.Me.Fake.fake_user!()
    someone = Bonfire.Me.Fake.fake_user!()
    stranger = Bonfire.Me.Fake.fake_user!()
    {:ok, acl} = Acls.simple_create(me, "a preset")
    post = Bonfire.Posts.Fake.fake_post!(me, "public")
    {:ok, me: me, someone: someone, stranger: stranger, acl: acl, post: post}
  end

  @checks [
    {Bonfire.Boundaries.Controlleds, :may_configure?, 2},
    {Bonfire.Boundaries.Acls, :may_edit?, 2},
    {Bonfire.Boundaries.Acls, :may_attach?, 2},
    {Bonfire.Boundaries, :can?, 4}
  ]

  # how many times each check ran while `fun` did, as `%{{module, function} => count}`
  defp count_checks(fun) do
    # a module that isn't loaded yet can't be given a trace pattern
    for {mod, _f, _a} <- @checks, do: Code.ensure_loaded!(mod)
    tracer = spawn_link(fn -> collect_calls(%{}) end)
    :erlang.trace(self(), true, [:call, {:tracer, tracer}])
    for mfa <- @checks, do: :erlang.trace_pattern(mfa, true, [:local])

    try do
      fun.()
    after
      :erlang.trace(self(), false, [:call])
      for mfa <- @checks, do: :erlang.trace_pattern(mfa, false, [:local])
    end

    send(tracer, {:done, self()})

    receive do
      {:counts, counts} -> counts
    after
      5000 -> flunk("the tracer didn't answer")
    end
  end

  defp collect_calls(acc) do
    receive do
      {:trace, _pid, :call, {m, f, _args}} ->
        collect_calls(Map.update(acc, {m, f}, 1, &(&1 + 1)))

      {:done, from} ->
        send(from, {:counts, acc})
    end
  end

  defp stored(acl, me) do
    Grants.list_for_acl(acl.id, current_user: me, skip_boundary_check: true)
    |> Enum.map(&{&1.verb_id, &1.value})
  end

  describe "a list of subjects" do
    test "`grant_role/4` refuses a user who may not edit the ACL, without raising", %{
      me: me,
      someone: someone,
      stranger: stranger,
      acl: acl
    } do
      assert {:error, :not_permitted} =
               Grants.grant_role([someone.id, me.id], acl.id, "read", current_user: stranger)

      assert stored(acl, me) == []
    end

    test "`grant_role/4` grants each of them for a user who may", %{
      me: me,
      someone: someone,
      acl: acl
    } do
      {:ok, can, _} = Bonfire.Boundaries.Roles.verbs_for_role("read", [])

      assert [_ | _] = Grants.grant_role([someone.id, me.id], acl.id, "read", current_user: me)

      assert length(stored(acl, me)) == 2 * length(can)
    end

    test "`remove_role/4` refuses a user who may not edit the ACL, without raising, and removes for one who may",
         %{me: me, someone: someone, stranger: stranger, acl: acl} do
      Grants.grant_role([someone.id, me.id], acl.id, "read", current_user: me)
      before = stored(acl, me)
      assert before != []

      assert {:error, :not_permitted} =
               Grants.remove_role([someone.id, me.id], acl.id, "read", current_user: stranger)

      assert stored(acl, me) == before

      assert [_ | _] = Grants.remove_role([someone.id, me.id], acl.id, "read", current_user: me)
      assert stored(acl, me) == []
    end

    test "`change_role/4` refuses a user who may not edit the ACL, without raising", %{
      me: me,
      someone: someone,
      stranger: stranger,
      acl: acl
    } do
      assert {:error, :not_permitted} =
               Grants.change_role([someone.id, me.id], acl.id, "read", current_user: stranger)

      assert stored(acl, me) == []
    end
  end

  describe "one call checks once" do
    test "`Grants.change_role/4` checks the ACL once", %{me: me, someone: someone, acl: acl} do
      checks =
        count_checks(fn ->
          assert [_ | _] = Grants.change_role(someone.id, acl.id, "read", current_user: me)
        end)

      assert checks[{Acls, :may_edit?}] == 1
    end

    test "`Acls.get_or_create_object_custom_acl/2` checks the object once when it creates the ACL",
         %{me: me, post: post} do
      checks =
        count_checks(fn ->
          assert {:ok, _acl} = Acls.get_or_create_object_custom_acl(post, current_user: me)
        end)

      assert checks[{Controlleds, :may_configure?}] == 1
      refute checks[{Acls, :may_attach?}]
    end

    test "`Controlleds.grant_role/4` checks the object once, and not the ACL again", %{
      me: me,
      someone: someone,
      post: post
    } do
      checks =
        count_checks(fn ->
          assert [_ | _] = Controlleds.grant_role(someone.id, post, "read", current_user: me)
        end)

      assert checks[{Controlleds, :may_configure?}] == 1
      refute checks[{Acls, :may_edit?}]
    end

    test "`Controlleds.regrant_role/5` checks the object once, and not the ACL again", %{
      me: me,
      someone: someone,
      post: post
    } do
      {:ok, _} = Acls.get_or_create_object_custom_acl(post, current_user: me)

      checks =
        count_checks(fn ->
          assert [_ | _] =
                   Controlleds.regrant_role(
                     someone.id,
                     post,
                     "contribute",
                     ["read", "contribute"], current_user: me)
        end)

      assert checks[{Controlleds, :may_configure?}] == 1
      refute checks[{Acls, :may_edit?}]
    end
  end

  describe "`Acls.may_edit?/2`" do
    test "lets an ACL's caretaker edit it without asking about the instance", %{
      me: me,
      acl: acl
    } do
      checks = count_checks(fn -> assert Acls.may_edit?(acl, current_user: me) end)

      refute checks[{Bonfire.Boundaries, :can?}],
             "the caretaker is known from one cheap query, before the instance's permissions"
    end

    test "still refuses a built-in ACL to someone who is not an instance admin", %{me: me} do
      refute Acls.may_edit?(Acls.get_id!(:guests_may_see_read), current_user: me)
    end
  end
end
