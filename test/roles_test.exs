defmodule Bonfire.Boundaries.RolesTest do
  @moduledoc """
  Locks the `preset_boundary_role_from_acl/1` 3-tuple contract.

  The function returns `{role_atom, localized_role_name, verbs}`. Callers
  branch on the locale-stable `role_atom` (`BoundaryDetailsLive` does
  `role_atom == :administer`) — earlier the function returned a 2-tuple
  `{role_name, "Full permissions"}` for `:administer`, which crashed
  `Enum.member?/2` checks against a non-list and was locale-fragile.
  """

  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries.Roles
  alias Bonfire.Boundaries.Verbs

  defp all_verb_names, do: Verbs.verbs() |> Enum.map(fn {_slug, %{verb: v}} -> v end)

  describe "preset_boundary_role_from_acl/1 — list input" do
    test ":administer case returns {:administer, name, verbs}" do
      verbs = all_verb_names()
      assert {role_atom, role_name, returned_verbs} = Roles.preset_boundary_role_from_acl(verbs)
      assert role_atom == :administer
      assert is_binary(role_name)
      # The verbs list MUST be returned (not the legacy "Full permissions"
      # string) so that downstream `is_list/1` checks and verb-membership
      # checks (e.g. `your_role_live.sface`'s `:for permission_or_verb <-
      # List.wrap(@role_permissions) |> sort_verbs()`) work correctly.
      assert is_list(returned_verbs)
      assert returned_verbs == verbs
    end

    test "non-:administer case returns {role_atom, name, verbs}" do
      # An empty verbs list doesn't match any preset role → falls back to :custom.
      assert {role_atom, role_name, returned_verbs} = Roles.preset_boundary_role_from_acl([])
      assert is_atom(role_atom)
      assert is_binary(role_name)
      assert returned_verbs == []
    end

    test "for a known named role, returns its atom and titled name" do
      # Reconstruct the verb-name list that the `:read` role grants, then
      # confirm round-trip identification: feeding those verbs back returns
      # `{:read, "Read", ^verbs}`. Locks the role-atom propagation that
      # `BoundaryDetailsLive`'s `role_atom == :administer` check relies on.
      read_verbs =
        Roles.role_verbs(:all)
        |> Map.fetch!(:read)
        |> Map.fetch!(:can_verbs)
        |> Enum.map(fn slug -> Verbs.get(slug)[:verb] end)
        |> Enum.sort()

      assert {:read, "Read", ^read_verbs} =
               Roles.preset_boundary_role_from_acl(read_verbs)
    end
  end

  describe "preset_boundary_role_from_acl/1 — summary map input" do
    test "delegates to the list arm and returns the same 3-tuple shape" do
      verbs = all_verb_names()

      assert {:administer, _, ^verbs} =
               Roles.preset_boundary_role_from_acl(%{verbs: verbs})
    end
  end
end
