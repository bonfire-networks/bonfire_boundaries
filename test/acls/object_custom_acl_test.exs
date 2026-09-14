defmodule Bonfire.Boundaries.ObjectCustomAclTest do
  @moduledoc """
  Every object can be given a per-object custom ACL, whatever preset it carries.

  This is what the boundary editor's "Advanced" panel hangs off: `BoundaryDetailsLive` splits an object's ACLs into named preset ones and unnamed custom ones, and renders the panel only when the custom list is non-empty, calling `get_or_create_object_custom_acl/2` to make one when there is none. A `public` post carries only named preset ACLs, so that call is the sole reason the panel appears at all, and four UI tests depend on it without naming it.

  It is also how `Controlleds.grant_role/4` and `regrant_role/5` reach an object's own ACL, so a failure here silently removes per-object grants as well as the editor.
  """
  use Bonfire.Boundaries.DataCase, async: false
  use Bonfire.Common.Utils
  @moduletag :backend

  alias Bonfire.Boundaries.Acls
  alias Bonfire.Me.Fake

  setup do
    # nothing here federates; publishing otherwise spawns federation tasks with no DB ownership in tests
    Process.put(:federating, false)
    :ok
  end

  for boundary <- ["public", "local", "mentions"] do
    test "a #{boundary} post can be given a custom ACL" do
      author = Fake.fake_user!()
      post = Bonfire.Posts.Fake.fake_post!(author, unquote(boundary))

      assert {:ok, acl} = Acls.get_or_create_object_custom_acl(post, author),
             "the Advanced boundary panel renders only when this answers, so a failure here shows up as a missing component rather than an error"

      assert uid(acl)
    end

    test "asking twice for a #{boundary} post's custom ACL returns the same one" do
      author = Fake.fake_user!()
      post = Bonfire.Posts.Fake.fake_post!(author, unquote(boundary))

      assert {:ok, first} = Acls.get_or_create_object_custom_acl(post, author)
      assert {:ok, second} = Acls.get_or_create_object_custom_acl(post, author)

      assert uid(first) == uid(second),
             "it is called on every render of the panel, so creating a new ACL each time would pile up rows and lose grants written against the previous one"
    end
  end
end
