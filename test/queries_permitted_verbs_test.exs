defmodule Bonfire.Boundaries.QueriesPermittedVerbsTest do
  @moduledoc """
  `permitted_verbs_on/3` answers which of several verbs a subject may perform on one object, in one query.

  The distinction it exists for is between "you may not do this" and "you may not even ask": `Follows.follow/3` refuses a follow and then has to decide whether falling back to a request is itself allowed. Asking about `[:follow, :request]` with `permitted_objects/2` cannot answer that, because grouping by object makes `bool_and` mean "permitted for ALL the verbs asked about", so one denied verb drops the object entirely. Grouping by verb judges each on its own grant rows.

  Two properties are easy to lose by computing this in Elixir over `Bonfire.Boundaries.users_grants_on/2` instead, so both are pinned here: negative grants win, and grants held by the built-in locality circles count.
  """
  use Bonfire.Boundaries.DataCase, async: false
  use Bonfire.Common.Utils
  @moduletag :backend

  alias Bonfire.Boundaries.Controlleds
  alias Bonfire.Boundaries.Queries
  alias Bonfire.Me.Fake

  setup do
    # nothing here federates; publishing otherwise spawns federation tasks with no DB ownership in tests
    Process.put(:federating, false)
    :ok
  end

  test "reports the verbs granted through a locality circle, not only those granted to the user directly" do
    author = Fake.fake_user!()
    reader = Fake.fake_user!()

    post = Bonfire.Posts.Fake.fake_post!(author, "public")

    verbs = Queries.permitted_verbs_on(reader, post, [:read, :see])

    assert :read in verbs,
           "a public post grants `:read` to the `local` circle rather than to this user, so a subject expansion that only looks at the user id would answer with nothing here"

    assert :see in verbs
  end

  test "omits a verb the subject was never granted" do
    author = Fake.fake_user!()
    reader = Fake.fake_user!()

    post = Bonfire.Posts.Fake.fake_post!(author, "public")

    refute :delete in Queries.permitted_verbs_on(reader, post, [:read, :delete]),
           "a reader of a public post cannot delete it, so the verb has to be absent rather than the call failing"

    assert :read in Queries.permitted_verbs_on(reader, post, [:read, :delete]),
           "the control: the same call does report the verb that IS granted, so the refusal above is about `:delete`"
  end

  test "a negative grant wins over a positive one" do
    author = Fake.fake_user!()
    reader = Fake.fake_user!()

    post = Bonfire.Posts.Fake.fake_post!(author, "public")

    assert :read in Queries.permitted_verbs_on(reader, post, [:read]),
           "the control: reading is granted before the denial is applied"

    Controlleds.grant_role(uid(reader), post, :cannot_read, current_user: author)

    refute :read in Queries.permitted_verbs_on(reader, post, [:read]),
           "negative precedence is the whole reason this stays in SQL; computing it from grouped grant rows is where a denial gets dropped"
  end

  test "asking about follow and request separately is what distinguishes refusing from forbidding the ask" do
    followed = Fake.fake_user!(%{}, %{}, request_before_follow: true)
    asker = Fake.fake_user!()

    verbs = Queries.permitted_verbs_on(asker, followed, [:follow, :request])

    refute :follow in verbs, "the account requires approval, so following outright is refused"

    assert :request in verbs,
           "but asking is still allowed, which is precisely the case `permitted_objects/2` cannot report since it would drop the object for the denied verb"
  end

  # `Boundaries.users_grants_on/2,3` share the same subject expansion, having previously filtered on the user's own id alone. Their callers are the boundary-display paths (`boundary_on_object/3`, `boundaries_on_objects/3`), so the symptom was the "your permissions on this object" UI reporting less than the user had and silently falling back to the preset.
  test "users_grants_on reports grants held via a locality circle" do
    author = Fake.fake_user!()
    reader = Fake.fake_user!()

    post = Bonfire.Posts.Fake.fake_post!(author, "public")

    assert [_ | _] = grants = Bonfire.Boundaries.users_grants_on(reader, post)

    assert Enum.any?(grants, &("Read" in (&1.verbs || []))),
           "a public post grants reading to the `local` circle rather than to this reader, so filtering on the reader's own id answers with nothing"
  end

  test "with no verbs given, reports everything permitted rather than filtering" do
    author = Fake.fake_user!()
    reader = Fake.fake_user!()

    post = Bonfire.Posts.Fake.fake_post!(author, "public")

    all = Queries.permitted_verbs_on(reader, post)
    subset = Queries.permitted_verbs_on(reader, post, [:read])

    assert :read in all
    assert subset == [:read]

    assert length(all) > length(subset),
           "omitting the filter has to widen the answer, otherwise the default is silently behaving like a filter"
  end
end
