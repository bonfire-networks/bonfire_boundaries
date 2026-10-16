defmodule Bonfire.Boundaries.QueriesVerbsOptsTest do
  @moduledoc """
  Which verbs a boundary query checks, read from its options by `Queries.verbs_from_opts/1`.

  The option is `verbs:`, a list (all of them) or `{:any, list}` (at least one), defaulting to `[:see]`, whether something may be listed. A singular `verb:` used to be ignored, so a fetch asking for `verb: :mediate` silently checked only the default. It is now taken as `verbs: [verb]`, but still errors so callers move to `verbs:`. Both at once is refused, since quietly picking one would hide the mistake.

  A singular `verb:` uses `err/2`, which raises in test and only logs in production, so it is asserted as a raise here and its production behaviour (checked as given) is not observable from a test. Both at once returns an error everywhere.
  """
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries.Queries

  test "`verbs:` is used as given" do
    assert {:ok, [:mediate]} = Queries.verbs_from_opts(verbs: [:mediate])
    assert {:ok, [:read]} = Queries.verbs_from_opts(verbs: :read)
    assert {:ok, {:any, [:see, :request]}} = Queries.verbs_from_opts(verbs: {:any, [:see, :request]})
  end

  # listing: opening one object asks for `[:read]`, and showing its content to whoever finds it `[:see, :read]`
  test "with neither, it checks whether it may be listed" do
    assert {:ok, [:see]} = Queries.verbs_from_opts(current_user: nil)
  end

  test "a singular `verb:` errors, so the caller is found and moved to `verbs:`" do
    assert_raise RuntimeError, fn -> Queries.verbs_from_opts(verb: :mediate) end
  end

  # refused everywhere, not only in test, so a query given both fails closed (`deny_all/1`)
  test "both at once is refused rather than merged" do
    assert {:error, _} = Queries.verbs_from_opts(verbs: [:read], verb: :mediate)
  end

  test "a refused verb option matches nothing" do
    query = Ecto.Query.from(v in Bonfire.Data.AccessControl.Verb)

    assert repo().all(query) != [], "control: the query matches something before being denied"
    assert repo().all(Queries.deny_all(query)) == []
  end
end
