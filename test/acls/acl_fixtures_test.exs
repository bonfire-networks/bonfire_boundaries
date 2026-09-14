defmodule Bonfire.Boundaries.AclFixturesTest do
  @moduledoc """
  Every ACL declared in config exists in the database, and every deprecated one does not.

  `Acls.get_id/1` answers from config without touching the database, so an ACL can be declared, referenced by a preset, and resolve to an id that has no row behind it. Nothing reports that directly: what surfaces is scattered `{:error, :not_permitted}` wherever the missing grants were needed. Adding `everyone_may_follow` did exactly this and failed 57 tests across three extensions, none of which named the cause — the ACL was in config, but the migration that creates ACL rows had already run and does not run twice.

  The reverse is checked too, because `deprecated` ACLs are deliberately excluded from fixtures (`Scaffold.Instance.config_current_acls/0`): they exist in config only so their ids keep resolving for instances that already hold rows pointing at them, and nothing new should ever be attached to one. That half is asked of the fixtures rather than the database, since an upgraded instance is supposed to still have the row.

  Excluding an ACL has a second half that is easy to miss: its GRANTS. `grants_fixtures/0` walks the whole grants config, so an ACL dropped from the ACL fixtures while keeping its grants entry leaves a fresh install inserting grants against an ACL nothing created.
  """
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  import Ecto.Query
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Data.AccessControl.Acl

  defp existing_acl_ids do
    repo().all(from(a in Acl, select: a.id))
    |> MapSet.new()
  end

  test "every live ACL in config has a row" do
    existing = existing_acl_ids()

    missing =
      Acls.acls()
      |> Enum.reject(fn {_slug, acl} -> acl[:deprecated] end)
      |> Enum.reject(fn {_slug, acl} -> acl[:id] in existing end)
      |> Enum.map(&elem(&1, 0))

    assert missing == [],
           "declared in config with no row, so anything granting through them silently permits nothing: #{inspect(missing)}. A new built-in ACL needs a migration calling `Scaffold.Instance.upsert_acls/0` — migrations run once, so adding one to an existing migration does not re-run it."
  end

  # Asked of the FIXTURES rather than of the database, because the database cannot answer it. A deprecated ACL's row is EXPECTED to exist on any instance that held it before the deprecation, which is the whole reason its config entry stays. Nothing deletes one, deliberately, since objects still point at it. So querying rows conflates "this install created it" with "it has been here since before", and would fail on every upgraded instance including a developer's own test database. What has to hold is that the scaffold never creates another.
  test "no deprecated ACL is created on a fresh install" do
    fixtures = Bonfire.Boundaries.Scaffold.Instance.fixtures()

    deprecated =
      Acls.acls()
      |> Enum.filter(fn {_slug, acl} -> acl[:deprecated] end)

    assert deprecated != [],
           "the control: there are deprecated ACLs to check, so the assertions below are not vacuous"

    created = fixtures.acls |> Enum.map(& &1[:id]) |> MapSet.new()

    present =
      deprecated
      |> Enum.filter(fn {_slug, acl} -> acl[:id] in created end)
      |> Enum.map(&elem(&1, 0))

    assert present == [],
           "a deprecated ACL exists in config only so its id keeps resolving for instances that already hold rows against it; creating one on a fresh install would let new objects attach to the wider legacy grants: #{inspect(present)}"

    # and the half that is easy to miss: an ACL excluded from the fixtures but still granted through leaves grant rows referencing an ACL nothing created
    granted =
      fixtures.grants
      |> Enum.map(& &1.acl_id)
      |> MapSet.new()

    granted_deprecated =
      deprecated
      |> Enum.filter(fn {_slug, acl} -> acl[:id] in granted end)
      |> Enum.map(&elem(&1, 0))

    assert granted_deprecated == [],
           "grants written against an ACL the fixtures do not create, so a fresh install gets rows pointing at nothing: #{inspect(granted_deprecated)}"
  end
end
