defmodule Bonfire.Boundaries.UserCirclesTest do
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend
  alias Bonfire.Data.AccessControl.Stereotyped
  alias Bonfire.Data.AccessControl.Controlled
  alias Absinthe.Blueprint.TypeReference.Name
  alias Bonfire.Data.AccessControl.Circle
  alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.AccessControl.Encircle
  alias Bonfire.Boundaries.Grants
  alias Bonfire.Me.Fake
  alias Bonfire.Me.Users
  alias Bonfire.Boundaries.Users
  alias Bonfire.Common.Config
  alias Bonfire.Boundaries.Circles

  describe "default boundaries from config should be inserted in the database when a new user is created" do
    test "nothing should be created if the configs are empty" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{},
        acls: %{},
        grants: %{},
        controlleds: %{}
      })

      %{id: user_id} = user = fake_user!()
      assert length(Circles.list_my(user)) == 0
      assert repo().one(from g in Grant, select: count(g), where: g.subject_id == ^user_id) == 0
    end

    test "circles should be created" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{
          test_circle: %{stereotype: :followers}
        },
        acls: %{},
        grants: %{},
        controlleds: %{}
      })

      %{id: user_id} = user = fake_user!()
      assert length(Circles.list_my(user)) == 1
    end

    test "grants should be created" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{},
        acls: %{},
        grants: %{
          i_may_administer: %{
            SELF: [:see]
          }
        },
        controlleds: %{}
      })

      %{id: user_id} = user = fake_user!()

      assert repo().one(from g in Grant, select: count(g), where: g.subject_id == ^user_id) == 1
    end
  end
end
