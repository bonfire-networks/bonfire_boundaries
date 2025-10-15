defmodule Bonfire.Boundaries.InitUserBoundariesTest do
  use Bonfire.Boundaries.DataCase, async: true
  @moduletag :backend
  alias Bonfire.Boundaries.Controlleds
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
  alias Bonfire.Boundaries.Scaffold.Users
  # use Bonfire.Common.Config
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Acls
  alias Bonfire.Common.Repo

  setup do
    on_exit(fn -> Process.delete([:bonfire, :user_default_boundaries]) end)
  end

  describe(
    "default boundaries from config should be inserted in the database when a new user is created"
  ) do
    test "nothing should be created if the configs are empty" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{},
        acls: %{},
        grants: %{},
        controlleds: %{}
      })

      %{id: user_id} = user = Bonfire.Me.Fake.fake_user!()
      assert length(Circles.list_my(user)) == 0
      assert repo().one(from g in Grant, select: count(g), where: g.subject_id == ^user_id) == 0
      # assert repo().one(from s in Stereotyped, select: count(s)) == 0
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

      user = Bonfire.Me.Fake.fake_user!()
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

      %{id: user_id} = Bonfire.Me.Fake.fake_user!()
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

      user = Bonfire.Me.Fake.fake_user!()

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

      %{id: user_id} = Bonfire.Me.Fake.fake_user!()

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

      %{id: user_id} = Bonfire.Me.Fake.fake_user!(%{}, %{}, undiscoverable: true)

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

      %{id: user_id} = Bonfire.Me.Fake.fake_user!()
      assert repo().one(from c in Controlled, select: count(c), where: c.id == ^user_id) == 4
    end

    test "a stereotyped circle or acl should not be duplicated on the db when created for two different users" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{
          followers: %{stereotype: :followers}
        },
        acls: %{
          i_may_administer: %{stereotype: :i_may_administer}
        },
        grants: %{},
        controlleds: %{}
      })

      user_1 = Bonfire.Me.Fake.fake_user!()
      user_2 = Bonfire.Me.Fake.fake_user!()
      [circle_1] = Circles.list_my(user_1)
      [circle_2] = Circles.list_my(user_2)
      [acl_1] = Acls.list_my(user_1, paginate?: false)
      [acl_2] = Acls.list_my(user_2, paginate?: false)

      # assert repo().one(from s in Stereotyped, select: count(s)) == 4

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

      %{id: user_id} = user = Bonfire.Me.Fake.fake_user!()
      Users.create_missing_boundaries(user)
      assert length(Circles.list_my(user)) == 0
      assert repo().one(from g in Grant, select: count(g), where: g.subject_id == ^user_id) == 0
      # repo().all(from(s in Stereotyped)) |> debug()
      # assert repo().one(from s in Stereotyped, select: count(s)) == 0
    end

    test "create missing circles" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{
          followers: %{stereotype: :followers}
        },
        acls: %{},
        grants: %{},
        controlleds: %{}
      })

      user = Bonfire.Me.Fake.fake_user!()
      [circle] = Circles.list_my(user)
      Circles.delete(circle, current_user: user)
      assert Circles.list_my(user) == []
      assert repo().one(from s in Stereotyped, select: count(s), where: s.id == ^circle.id) == 0
      Users.create_missing_boundaries(user)
      [circle] = Circles.list_my(user)
      assert circle.stereotyped.named.name == "People who follow me"
    end

    test "create missing acls" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{},
        acls: %{
          i_may_administer: %{stereotype: :i_may_administer}
        },
        grants: %{},
        controlleds: %{}
      })

      user = Bonfire.Me.Fake.fake_user!()
      [acl] = Acls.list_my(user, paginate?: false)
      Acls.delete(acl, current_user: user)
      assert Acls.list_my(user, paginate?: false) == []
      assert repo().one(from s in Stereotyped, select: count(s), where: s.id == ^acl.id) == 0
      Users.create_missing_boundaries(user)
      [acl] = Acls.list_my(user, paginate?: false)

      assert acl.stereotyped.named.name == "I may administer"
    end

    test "create missing controlleds" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{},
        acls: %{},
        grants: %{},
        controlleds: %{
          SELF: [
            :locals_may_reply
          ]
        }
      })

      %{id: user_id} = user = Bonfire.Me.Fake.fake_user!()

      assert repo().one(from c in Controlled, select: count(c), where: c.id == ^user_id) == 2
      repo().delete_many(from c in Controlled, where: c.id == ^user_id)
      assert repo().one(from c in Controlled, select: count(c), where: c.id == ^user_id) == 0
      Users.create_missing_boundaries(user)

      [
        %Bonfire.Data.AccessControl.Controlled{
          acl_id: "710CA1SMY1NTERACTANDREP1YY"
        }
        # FIXME: is this correct?
        # %Bonfire.Data.AccessControl.Controlled{
        #   acl_id: "7W1DE1YAVA11AB1ET0SEENREAD"
        # }
      ] = repo().all(from c in Controlled, where: c.id == ^user_id)
    end

    test "create missing grants" do
      Process.put([:bonfire, :user_default_boundaries], %{
        circles: %{},
        acls: %{
          i_may_administer: %{stereotype: :i_may_administer}
        },
        grants: %{
          i_may_administer: %{
            SELF: [:see, :read]
          }
        },
        controlleds: %{}
      })

      %{id: user_id} = user = Bonfire.Me.Fake.fake_user!()
      assert repo().one(from g in Grant, select: count(g), where: g.subject_id == ^user_id) == 2
      repo().delete_many(from c in Grant, where: c.subject_id == ^user_id)
      assert repo().one(from c in Grant, select: count(c), where: c.subject_id == ^user_id) == 0
      Users.create_missing_boundaries(user)

      [
        %Bonfire.Data.AccessControl.Grant{subject_id: sub_id_1},
        %Bonfire.Data.AccessControl.Grant{subject_id: sub_id_2}
      ] = repo().all(from c in Grant, where: c.subject_id == ^user_id)

      assert sub_id_1 == sub_id_2
      assert sub_id_1 == user_id
    end
  end
end
