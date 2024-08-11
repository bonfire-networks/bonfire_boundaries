defmodule Bonfire.Boundaries.InitUserBoundariesTest do
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend
  alias Erl2exVendored.Pipeline.Names
  alias Credo.Check.Refactor.ABCSize
  # alias Bonfire.Boundaries.Controlleds
  alias Bonfire.Data.AccessControl.Stereotyped
  alias Bonfire.Data.AccessControl.Controlled
  # alias Absinthe.Blueprint.TypeReference.Name
  # alias Bonfire.Data.AccessControl.Circle
  # alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.AccessControl.Grant
  alias Bonfire.Data.AccessControl.Named
  # alias Bonfire.Boundaries.Grants
  # alias Bonfire.Me.Fake
  # alias Bonfire.Me.Users
  alias Bonfire.Boundaries.Users
  # alias Bonfire.Common.Config
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Common.Repo

  describe(
    "default boundaries from config should be inserted in the database when a new user is created"
  ) do
    setup do
      on_exit(fn -> Process.delete([:bonfire, :user_default_boundaries]) end)
    end

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
      assert repo().one(from s in Stereotyped, select: count(s)) == 0
    end

    test "circles should be created" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{
          test_circle: %{id: "test", name: "test_name"}
        },
        acls: %{},
        grants: %{},
        controlleds: %{}
      })

      user = fake_user!()
      [circle] = Circles.list_my(user)
      assert circle.named.name == "test_name"
    end

    test "grants should be created" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{},
        acls: %{},
        grants: %{
          i_may_administer: %{
            SELF: [:see, :read]
          }
        },
        controlleds: %{}
      })

      %{id: user_id} = fake_user!()
      assert repo().one(from g in Grant, select: count(g), where: g.subject_id == ^user_id) == 2
    end

    test "acls should be created" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{},
        acls: %{abc: %{id: "test", name: "test_name"}},
        grants: %{
          abc: %{
            SELF: [:see, :read]
          }
        },
        controlleds: %{}
      })

      user = fake_user!()

      [acl] = Acls.list_my(user, paginate?: false)
      assert acl.named.name == "test_name"
    end

    test "default discover/read controlleds should be created" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{},
        acls: %{},
        grants: %{},
        controlleds: %{SELF: []}
      })

      %{id: user_id} = fake_user!()

      assert %Bonfire.Data.AccessControl.Controlled{acl_id: "7W1DE1YAVA11AB1ET0SEENREAD"} =
               repo().one(from c in Controlled, where: c.id == ^user_id)

      assert repo().one(from c in Controlled, select: count(c), where: c.id == ^user_id) == 1
    end

    test "specified discover/read controlleds should be created" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{},
        acls: %{},
        grants: %{},
        controlleds: %{SELF: []}
      })

      %{id: user_id} = fake_user!(%{}, %{}, undiscoverable: true)

      assert %Bonfire.Data.AccessControl.Controlled{acl_id: "50VCANREAD1FY0VHAVETHE11NK"} =
               repo().one(from c in Controlled, where: c.id == ^user_id)

      assert repo().one(from c in Controlled, select: count(c), where: c.id == ^user_id) == 1
    end

    test "controlleds should be created" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{},
        acls: %{},
        grants: %{},
        controlleds: %{
          SELF: [
            :locals_may_reply,
            :remotes_may_reply,
            :i_may_administer
          ]
        }
      })

      %{id: user_id} = fake_user!()
      assert repo().one(from c in Controlled, select: count(c), where: c.id == ^user_id) == 4
    end

    test "a stereotyped circle or acl should not be duplicated on the db when created for two different users" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{
          followers: %{
            id: "7DAPE0P1E1PERM1TT0F0110WME",
            name: "Those who follow me",
            stereotype: :followers
          }
        },
        acls: %{
          i_may_administer: %{
            id: "71MAYADM1N1STERMY0WNSTVFFS",
            name: "I may administer",
            stereotype: :i_may_administer
          }
        },
        grants: %{},
        controlleds: %{}
      })

      user_1 = fake_user!()
      user_2 = fake_user!()
      [circle_1] = Circles.list_my(user_1)
      [circle_2] = Circles.list_my(user_2)
      [acl_1] = Acls.list_my(user_1, paginate?: false)
      [acl_2] = Acls.list_my(user_2, paginate?: false)

      assert repo().one(from s in Stereotyped, select: count(s)) == 4

      assert circle_1.stereotyped.stereotype_id ==
               repo().one(from s in Stereotyped, where: s.id == ^circle_1.id).stereotype_id

      assert circle_2.stereotyped.stereotype_id ==
               repo().one(from s in Stereotyped, where: s.id == ^circle_2.id).stereotype_id

      assert acl_1.stereotyped.stereotype_id ==
               repo().one(from s in Stereotyped, where: s.id == ^acl_1.id).stereotype_id

      assert acl_2.stereotyped.stereotype_id ==
               repo().one(from s in Stereotyped, where: s.id == ^acl_2.id).stereotype_id
    end
  end

  describe "create_missing_boundaries should" do
    setup do
      on_exit(fn -> Process.delete([:bonfire, :user_default_boundaries]) end)
    end

    test "do nothing if no boundaries are present and no boundaries are to be introduced" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{},
        acls: %{},
        grants: %{},
        controlleds: %{}
      })

      %{id: user_id} = user = fake_user!()
      Users.create_missing_boundaries(user)
      assert length(Circles.list_my(user)) == 0
      assert repo().one(from g in Grant, select: count(g), where: g.subject_id == ^user_id) == 0
      assert repo().one(from s in Stereotyped, select: count(s)) == 0
    end

    test "create missing circles" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{
          # users who have followed you
          followers: %{stereotype: :followers}
        },
        acls: %{},
        grants: %{},
        controlleds: %{}
      })

      user = fake_user!()
      [circle] = Circles.list_my(user)
      Circles.delete(circle, current_user: user)
      assert Circles.list_my(user) == []
      assert repo().one(from s in Stereotyped, select: count(s), where: s.id == ^circle.id) == 0
      Users.create_missing_boundaries(user)
      [circle] = Circles.list_my(user)

      assert circle.named.name == "test_name"
    end
  end
end
