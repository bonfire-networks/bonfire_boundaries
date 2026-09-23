defmodule Bonfire.Boundaries.PermissionProbeSqlTest do
  @moduledoc """
  The viewer's circle memberships inside each `:direct_exists` probe must be an uncorrelated `ARRAY(subquery)` InitPlan, costed and executed once per statement. Cost-model rationale: the comment on `permission_probe/5`.

  Asserted on the statement and its plan rather than on timing, because the property is about what the planner is asked to cost, and that holds at any data size: a dev-sized database shows the same shapes as a production one, where the nested form's estimate reached tens of millions and took the notifications feed past its statement timeout.
  """
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  import Ecto.Query
  alias Bonfire.Boundaries.Queries

  defp boundarised_sql(user) do
    query =
      from(p in Bonfire.Data.Social.Post, as: :main_object)
      |> Queries.object_boundarised(current_user: user, boundarise_strategy: :direct_exists)

    repo().to_sql(:all, query)
  end

  test "membership check is `= ANY(ARRAY(subquery))`, not `IN (subquery)`" do
    user = Bonfire.Me.Fake.fake_user!()
    {sql, _params} = boundarised_sql(user)

    assert sql =~ "= ANY(ARRAY("
    refute sql =~ ~r/"subject_id" IN \(SELECT/
  end

  test "planner turns the membership lookup into an InitPlan" do
    user = Bonfire.Me.Fake.fake_user!()
    {sql, params} = boundarised_sql(user)

    %{rows: rows} = Ecto.Adapters.SQL.query!(repo(), "EXPLAIN " <> sql, params)
    plan = rows |> List.flatten() |> Enum.join("\n")

    # the refute is the specific half: the `IN (subquery)` form plans as a `hashed SubPlan`, and it also keeps an unrelated InitPlan elsewhere in the query from making the assert pass on its own
    assert plan =~ "InitPlan"
    refute plan =~ "hashed SubPlan"
  end
end
