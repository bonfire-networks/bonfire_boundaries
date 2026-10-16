defmodule Bonfire.Boundaries.CanOrUnloadedTest do
  @moduledoc """
  Unit tests for `Bonfire.Boundaries.can_or_unloaded?/3` — the optimistic
  permission helper used by per-activity action button templates (boost, like,
  reply, quote) to avoid n+1 verb-permission DB queries when the surrounding
  `update_many` boundary preload hasn't completed.
  """

  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend

  alias Bonfire.Boundaries
  alias Bonfire.Me.Fake

  # the shape `Boundaries.boundaries_on_objects/3` loads, with the viewer's verbs
  defp loaded(verbs, object_id \\ "01HB0ABCDEFGHJKMNPQRSTVWXY"),
    do: %{id: object_id, object_id: object_id, verbs: verbs, preset: nil}

  describe "can_or_unloaded?/3" do
    test "returns true (optimistic) when there is no current user" do
      assert Boundaries.can_or_unloaded?(%{}, :like, nil)
      assert Boundaries.can_or_unloaded?(%{current_user: nil}, :boost, loaded([]))
    end

    test "returns true when object_boundary is nil" do
      user = Fake.fake_user!()
      assert Boundaries.can_or_unloaded?(%{current_user: user}, :like, nil)
    end

    test "returns true when object_boundary is :skip_boundary_preload" do
      user = Fake.fake_user!()

      assert Boundaries.can_or_unloaded?(
               %{current_user: user},
               :like,
               :skip_boundary_preload
             )
    end

    test "delegates to can?/3 (returns true) when boundary is preloaded and verb is granted" do
      user = Fake.fake_user!()

      assert Boundaries.can_or_unloaded?(
               %{current_user: user},
               :like,
               loaded(["Like", "Read", "See"])
             )
    end

    test "delegates to can?/3 (returns false) when boundary is preloaded and verb is missing" do
      user = Fake.fake_user!()

      refute Boundaries.can_or_unloaded?(%{current_user: user}, :like, loaded(["Read", "See"]))
    end

    test "passes through a verb list to can?/3" do
      # `can?/3` accepts either a single verb atom or a list. Templates that
      # check multiple verbs at once (e.g. `can?(ctx, [:see, :read], boundary)`)
      # must still benefit from the same in-memory fast path.
      user = Fake.fake_user!()
      boundary = loaded(["Like", "Read", "See"])

      assert Boundaries.can_or_unloaded?(%{current_user: user}, [:like, :read], boundary)
      refute Boundaries.can_or_unloaded?(%{current_user: user}, [:like, :boost], boundary)
    end

    # no verbs loaded (no grants of the viewer's to load): asked about as the object it names, in the database
    test "with no verbs loaded, asks about the object itself" do
      user = Fake.fake_user!()
      author = Fake.fake_user!()

      publish = fn boundary ->
        {:ok, post} =
          Bonfire.Posts.publish(
            current_user: author,
            post_attrs: %{post_content: %{html_body: "a #{boundary} post"}},
            boundary: boundary
          )

        loaded(nil, id(post))
      end

      assert Boundaries.can_or_unloaded?(%{current_user: user}, :like, publish.("public"))
      refute Boundaries.can_or_unloaded?(%{current_user: user}, :like, publish.("mentions"))
    end
  end
end
