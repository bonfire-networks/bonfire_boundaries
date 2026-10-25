defmodule Bonfire.Boundaries.RolesFromGrantsTest do
  @moduledoc """
  Covers `Roles.role_from_grants/2` with `fallback_to_list: true`: when grants match no role, it lists them as "Can %{verb}" / "Cannot %{verb}". The verb sits mid-sentence, so it is lowercase.
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
end
