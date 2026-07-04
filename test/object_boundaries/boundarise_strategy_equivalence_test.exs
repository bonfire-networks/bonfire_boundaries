defmodule Bonfire.Boundaries.BoundariseStrategyEquivalenceTest do
  @moduledoc """
  The `:direct_exists` boundarise strategy (EXISTS/NOT-EXISTS index probes) must produce EXACTLY the same visible-object sets as the legacy summary strategies (the Ecto-replica default and the SQL view), across every boundary shape that exercises a distinct part of the semantics, including the tricky ones: deny-via-circle (a `false` grant to a circle the viewer is in must veto) and cross-verb aggregation (a deny on ONE of the requested verbs vetoes the whole check, even when the other verb is granted).
  """
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  import Ecto.Query
  alias Bonfire.Boundaries.{Acls, Circles, Grants, Blocks, Queries}
  alias Bonfire.Posts

  @strategies [
    summary_subquery: [boundarise_strategy: :summary_subquery],
    summary_view: [boundarise_strategy: :view],
    direct_exists: [boundarise_strategy: :direct_exists]
  ]

  defp visible_ids(subject, strategy_opts) do
    from(p in Bonfire.Data.Social.Post, as: :main_object)
    |> Queries.object_boundarised([current_user: subject] ++ strategy_opts)
    |> repo().all()
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  defp assert_equivalent_visibility(subjects, expected_by_subject) do
    for {subject_label, subject} <- subjects do
      expected = Map.fetch!(expected_by_subject, subject_label)

      for {strategy, strategy_opts} <- @strategies do
        visible = visible_ids(subject, strategy_opts)

        assert visible == expected,
               "strategy #{strategy} for #{subject_label}: expected #{inspect(MapSet.to_list(expected))}, got #{inspect(MapSet.to_list(visible))}"
      end
    end
  end

  defp publish!(user, opts) do
    attrs = %{post_content: %{html_body: "equivalence fixture #{Text.random_string()}"}}
    assert {:ok, post} = Posts.publish([current_user: user, post_attrs: attrs] ++ opts)
    post.id
  end

  test "all strategies agree on visibility across boundary shapes" do
    author = Bonfire.Me.Fake.fake_user!()
    bob = Bonfire.Me.Fake.fake_user!()
    carol = Bonfire.Me.Fake.fake_user!()

    # a circle containing bob, used for both a positive custom-circle grant and a circle deny
    {:ok, circle} = Circles.create(author, %{named: %{name: "besties"}})
    {:ok, _} = Circles.add_to_circles(bob.id, circle)

    public = publish!(author, boundary: "public")
    local = publish!(author, boundary: "local")
    private = publish!(author, boundary: "mentions")
    to_circle = publish!(author, boundary: "mentions", to_circles: [circle.id])

    # direct per-user deny: public post, then a `false` :read grant straight to bob on the
    # post's own ACL — deny must win over the public preset's `true` grants
    denied_direct = publish!(author, boundary: "public")

    {:ok, acl} =
      Acls.get_or_create_object_custom_acl(denied_direct, author)

    Grants.grant(bob.id, acl.id, :read, false, skip_boundary_check: true)

    # cross-verb: deny only :see — with the check spanning [:see, :read], the single-verb
    # deny must veto even though :read stays granted by the preset
    denied_cross_verb = publish!(author, boundary: "public")

    {:ok, acl2} =
      Acls.get_or_create_object_custom_acl(denied_cross_verb, author)

    Grants.grant(bob.id, acl2.id, :see, false, skip_boundary_check: true)

    # deny-via-circle: author ghosts carol, which puts carol in the ghost_them circle whose
    # ACL holds `false` grants on everything: carol must lose ALL the author's objects
    {:ok, _} = Blocks.block(carol, :ghost, current_user: author)

    all = MapSet.new([public, local, private, to_circle, denied_direct, denied_cross_verb])
    publics = MapSet.new([public, denied_direct, denied_cross_verb])

    assert_equivalent_visibility(
      [author: author, bob: bob, carol: carol, anon: nil],
      %{
        # author sees everything of their own
        author: all,
        # bob: public+local+circle-granted, minus the two posts denying bob specifically
        bob: MapSet.new([public, local, to_circle]),
        # carol is ghosted by the author: nothing, despite public boundaries
        carol: MapSet.new([]),
        # anon sees only public posts — including the ones denying BOB (denies are per-subject)
        anon: publics
      }
    )
  end
end
