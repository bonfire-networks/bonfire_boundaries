defmodule Bonfire.Boundaries.QueriesSubjectCirclesTest do
  @moduledoc """
  Pins down how `Bonfire.Boundaries.Queries.query_with_summary/3` picks the
  extra subject circle (`:local` vs `:activity_pub`) — every boundarised query
  checks permissions not just for the subject's own id but also for the circle
  matching their locality, so getting this wrong changes what a subject can see.

  Documents three issues found while profiling page loads (the failing,
  `:todo`-tagged tests describe the DESIRED behavior — run them with
  `--include todo` to see the current behavior they demonstrate):

  1. N+1: for a subject struct without `:peered` loaded, `is_local?/2`
     preloads `[:peered, created: [creator: :peered]]` on EVERY query build
     and throws the result away, so the same single-row lookups repeat for
     every boundarised query in a request.
     (Mitigated for the session user: `Users.get_current/1,2` marks `peered:
     nil` since session users are always local — covered by a regression test
     below — but any other subject struct still pays it.)

  2. Inconsistency: a subject passed as a bare user ID falls into the
     list-of-subjects clause, which adds NO locality circle at all (just logs
     a warning) — so the same local user gets `:local`-circle visibility when
     passed as a struct but not when passed as an id. Note the
     `query_with_summary/2` docstring itself shows a binary-id call.

  3. Unsafe default: `is_local?/2` returns `true` for shapes it cannot
     classify, so a REMOTE subject passed as a bare `%{id: ...}` map is
     granted the `:local` circle.
  """
  use Bonfire.Boundaries.DataCase, async: false
  @moduletag :backend

  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Queries
  alias Bonfire.Me.Fake
  alias Bonfire.Me.Users

  import Tesla.Mock

  setup do
    # fake_remote_user fetches the mocked actor over (mocked) HTTP
    mock_global(fn env -> ActivityPub.Test.HttpRequestMock.request(env) end)
    :ok
  end

  defp circle_id(slug), do: Circles.circles()[slug][:id]

  # the subject_ids land in the query as one array parameter (of raw 16-byte
  # uids — decode them back to ULID strings for comparison with circle ids)
  defp subject_param_ids(subject) do
    {_sql, params} =
      repo().to_sql(:all, Queries.query_with_summary(subject, [:read]))

    params
    |> List.flatten()
    |> Enum.map(fn
      <<_::binary-size(16)>> = bin ->
        case Needle.UID.load(bin) do
          {:ok, str} -> str
          _ -> bin
        end

      other ->
        other
    end)
  end

  # Counts queries matching `regex` issued while running `fun` from this test
  # (including from Ecto preloader Tasks, via the $callers chain).
  defp with_query_count(regex, fun) do
    table = :ets.new(:subject_circles_query_count, [:public])
    test_pid = self()
    handler_id = "subject-circles-#{inspect(test_pid)}"
    repo_event = Bonfire.Common.Config.repo().config()[:telemetry_prefix] ++ [:query]

    :telemetry.attach(
      handler_id,
      repo_event,
      fn _event, _measurements, md, _config ->
        callers = [self() | Process.get(:"$callers") || []]

        if test_pid in callers and is_binary(md[:query]) and Regex.match?(regex, md[:query]) do
          :ets.update_counter(table, :count, 1, {:count, 0})
        end
      end,
      nil
    )

    try do
      result = fun.()

      count =
        case :ets.lookup(table, :count) do
          [{:count, n}] -> n
          _ -> 0
        end

      {result, count}
    after
      :telemetry.detach(handler_id)
    end
  end

  @peered_or_created ~r/bonfire_data_activity_pub_peered|bonfire_data_social_created/

  describe "locality circle selection (current behavior)" do
    test "a local user struct gets the :local circle, not :activity_pub" do
      user = Fake.fake_user!()

      ids = subject_param_ids(user)

      assert circle_id(:local) in ids
      refute circle_id(:activity_pub) in ids
      assert uid(user) in ids
    end

    test "a remote user with :peered loaded gets the :activity_pub circle, not :local" do
      {:ok, remote} = Bonfire.Federate.ActivityPub.Simulate.fake_remote_user()
      remote = repo().maybe_preload(remote, :peered)
      assert %{peered: %{id: _}} = remote

      ids = subject_param_ids(remote)

      assert circle_id(:activity_pub) in ids
      refute circle_id(:local) in ids
    end

    test "a remote user with marked :peered gets :activity_pub with ZERO extra queries" do
      {:ok, remote} = Bonfire.Federate.ActivityPub.Simulate.fake_remote_user()
      # even with top-level :peered NotLoaded, the marked character.peered classifies it for free
      remote = Map.put(remote, :peered, %Ecto.Association.NotLoaded{__field__: :peered})

      {ids, query_count} =
        with_query_count(@peered_or_created, fn -> subject_param_ids(remote) end)

      assert circle_id(:activity_pub) in ids
      refute circle_id(:local) in ids
      assert query_count == 0
    end

    test "REGRESSION: a session user from Users.get_current is classified with ZERO extra queries" do
      # session users are always local, so get_current marks peered as
      # loaded-and-absent — is_local? must short-circuit without queries
      user = Fake.fake_user!()
      current = Users.get_current(uid(user))
      assert %{character: %{peered: nil}} = current

      {ids, query_count} =
        with_query_count(@peered_or_created, fn -> subject_param_ids(current) end)

      assert circle_id(:local) in ids
      refute circle_id(:activity_pub) in ids
      assert query_count == 0
    end
  end

  describe "known issues (desired behavior, currently failing — run with --include todo)" do
    @tag :todo
    test "building boundarised queries repeatedly with the same subject must not re-preload :peered each time (N+1)" do
      {:ok, remote} = Bonfire.Federate.ActivityPub.Simulate.fake_remote_user()
      remote = Map.put(remote, :peered, %Ecto.Association.NotLoaded{__field__: :peered})

      {_ids, query_count} =
        with_query_count(@peered_or_created, fn ->
          # simulates several boundarised queries in one request/page load
          subject_param_ids(remote)
          subject_param_ids(remote)
          subject_param_ids(remote)
        end)

      # the classification (or the preloaded subject) should be reused: at most
      # one preload round, not one per query build
      assert query_count <= 2,
             "expected the peered/created preload to run at most once, got #{query_count} queries"
    end

    @tag :todo
    test "a local user passed as a bare ID should get the same :local circle as when passed as a struct" do
      user = Fake.fake_user!()

      ids = subject_param_ids(uid(user))

      assert uid(user) in ids

      assert circle_id(:local) in ids,
             "binary-id subjects fall into the list clause which skips locality circles entirely"
    end

    @tag :todo
    test "a remote subject passed as a bare %{id: ...} map must NOT be granted the :local circle" do
      {:ok, remote} = Bonfire.Federate.ActivityPub.Simulate.fake_remote_user()

      ids = subject_param_ids(%{id: uid(remote)})

      refute circle_id(:local) in ids,
             "is_local? defaults to true for unclassifiable shapes, granting remote subjects local-circle visibility"
    end
  end
end
