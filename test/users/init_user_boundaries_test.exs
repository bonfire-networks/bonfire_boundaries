defmodule Bonfire.Boundaries.InitUserBoundariesTest do
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend
  alias Credo.Check.Refactor.ABCSize
  # alias Bonfire.Boundaries.Controlleds
  # alias Bonfire.Data.AccessControl.Stereotyped
  alias Bonfire.Data.AccessControl.Controlled
  # alias Absinthe.Blueprint.TypeReference.Name
  # alias Bonfire.Data.AccessControl.Circle
  # alias Bonfire.Data.AccessControl.Acl
  alias Bonfire.Data.AccessControl.Grant
  # alias Bonfire.Data.AccessControl.Encircle
  # alias Bonfire.Boundaries.Grants
  # alias Bonfire.Me.Fake
  # alias Bonfire.Me.Users
  # alias Bonfire.Boundaries.Users
  # alias Bonfire.Common.Config
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Acls

  describe "default boundaries from config should be inserted in the database when a new user is created" do
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
      assert repo().one(from s in Stereotyped, select: count(s))==0
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

      user = fake_user!()
      assert length(Circles.list_my(user)) == 1
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
        acls: %{i_may_administer: %{stereotype: :i_may_administer}},
        grants: %{
          i_may_administer: %{
            SELF: [:see, :read]
          }
        },
        controlleds: %{}
      })

      user = fake_user!()

      assert length(Acls.list_my(user, paginate?: false)) == 1
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

      %{id: user_id} = user = fake_user!()
      assert repo().one(from c in Controlled, select: count(c), where: c.id == ^user_id) == 4
    end
  end

  test "stereotypes with the same name in different entries should not be duplicated on the db" do
    Process.put([:bonfire, :user_default_boundaries], %{
      circles: %{
        ABC: %{stereotype: :followers}
      },
      acls: %{i_may_administer: %{stereotype: :i_may_administer}},
      grants: %{
        i_may_administer: %{
          ABC: [:see, :read]
        }
      },
      controlleds: %{
        ABC: [
          :locals_may_reply,
          :remotes_may_reply,
          :i_may_administer
        ]
      }
    })

    fake_user!()
    #ABC is in different maps but it creates only one entry
    assert repo().one(from s in Stereotyped, select: count(s))==1
  end

  describe "creation of multiple users" do
end
end
