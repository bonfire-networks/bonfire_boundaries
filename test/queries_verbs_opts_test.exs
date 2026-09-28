defmodule Bonfire.Boundaries.QueriesVerbsOptsTest do
  @moduledoc """
  Which verbs a boundary query checks, read from its options by `Queries.verbs_from_opts/1`.

  The option is `verbs:`. A singular `verb:` used to be ignored, so a fetch asking for `verb: :mediate` silently checked only the default `:see`/`:read`. It is now taken as `verbs: [verb]`, but still errors so callers move to `verbs:`. Both at once is refused: `verbs:` passes anyone holding ANY of the listed verbs, so merging would widen the check.

  A singular `verb:` uses `err/2`, which raises in test and only logs in production, so it is asserted as a raise here and its production behaviour (checked as given) is not observable from a test. Both at once returns an error everywhere.
  """
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries.Queries

  test "`verbs:` is used as given" do
    assert {:ok, [:mediate]} = Queries.verbs_from_opts(verbs: [:mediate])
    assert {:ok, [:read]} = Queries.verbs_from_opts(verbs: :read)
  end

  test "with neither, it checks seeing and reading" do
    assert {:ok, [:see, :read]} = Queries.verbs_from_opts(current_user: nil)
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
