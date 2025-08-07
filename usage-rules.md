# Bonfire.Boundaries Usage Rules

Bonfire.Boundaries provides a flexible access control system for managing user permissions and data visibility. It implements a sophisticated boundary system using ACLs (Access Control Lists), Circles, Grants, and Verbs to control who can see and do what.

## Core Concepts

### Boundaries System
A comprehensive permission framework that controls access to objects and actions through:
- **Circles**: Groups of users (e.g., friends, colleagues)
- **Verbs**: Actions users can perform (e.g., read, edit, delete)
- **Grants**: Permission rules linking subjects to verbs with allow/deny values
- **ACLs**: Collections of grants that define access rules
- **Controlled**: Links objects to ACLs to apply boundaries

### Permission Values
Three possible permission states:
- `true`: Action is explicitly allowed
- `false`: Action is explicitly denied (takes precedence)
- `nil`: No explicit permission (defaults to denied)

### Permission Precedence
When multiple permissions apply: `false > true > nil`
- Explicit denial always wins
- Explicit allowance overrides absence
- No permission means no access

## Core Module Setup

```elixir
defmodule MyApp.Boundaries do
  use Bonfire.Common.Utils
  import Bonfire.Boundaries.Integration
  
  # Your boundary management functions
end
```

## Basic Usage

### Checking Permissions

```elixir
# Check if a user can perform an action
Bonfire.Boundaries.can?(current_user, :read, object)
# => true/false

# Check multiple verbs
Bonfire.Boundaries.can?(current_user, [:read, :edit], object)

# Raise if not permitted
Bonfire.Boundaries.can!(current_user, :delete, object)
```

### Creating Circles

```elixir
# Create a new circle
{:ok, circle} = Bonfire.Boundaries.Circles.create(current_user, %{
  named: %{name: "Close Friends"}
})

# Add users to a circle
Bonfire.Boundaries.Circles.add_to_circles([user1, user2], circle)

# Check if user is in circle
Bonfire.Boundaries.Circles.is_encircled_by?(user, circle)
```

### Creating ACLs

```elixir
# Simple ACL creation
{:ok, acl} = Bonfire.Boundaries.Acls.simple_create(current_user, "Project Team")

# Create ACL with grants
{:ok, acl} = Bonfire.Boundaries.Acls.create(%{
  named: %{name: "Collaborators"},
  grants: [
    %{subject_id: circle.id, verb_id: "read", value: true},
    %{subject_id: user.id, verb_id: "edit", value: true}
  ]
}, current_user: current_user)
```

## API Patterns

### Boundary Presets

```elixir
# Get default boundaries
boundaries = Bonfire.Boundaries.default_boundaries(current_user: user)
# => [{"public", "Public"}] or [{"local", "Local"}]

# Set boundaries on an object
{:ok, :granted} = Bonfire.Boundaries.set_boundaries(
  creator,
  object,
  boundary: "public"
)

# Replace existing boundaries
{:ok, :granted} = Bonfire.Boundaries.set_boundaries(
  creator,
  object,
  boundary: "local",
  remove_previous_preset: "public"
)
```

### Grant Management

```elixir
# Grant permissions
Bonfire.Boundaries.Grants.grant(
  circle.id,
  acl.id,
  [:read, :reply],
  true,
  current_user: user
)

# Grant role-based permissions
Bonfire.Boundaries.Grants.grant_role(
  user.id,
  acl,
  :interact,
  true,
  current_user: admin
)

# Remove grant
Bonfire.Boundaries.Grants.remove(subject, acl, verb)
```

### Blocking Users

```elixir
# Block a user (current user's scope)
{:ok, msg} = Bonfire.Boundaries.Blocks.block(blocked_user, :silence, current_user: blocker)

# Ghost a user (they can't see you)
{:ok, msg} = Bonfire.Boundaries.Blocks.block(blocked_user, :ghost, current_user: blocker)

# Instance-wide block (admin only)
{:ok, msg} = Bonfire.Boundaries.Blocks.block(blocked_user, :silence, :instance_wide)

# Unblock
{:ok, msg} = Bonfire.Boundaries.Blocks.unblock(blocked_user, :silence, current_user: blocker)
```

## Advanced Patterns

### Complex Permission Checks

```elixir
# Check with options
can_edit = Bonfire.Boundaries.can?(
  current_user,
  :edit,
  object,
  skip_boundary_check: false
)

# Batch check permissions on multiple objects
objects_with_boundaries = Bonfire.Boundaries.boundaries_on_objects(
  [object1.id, object2.id],
  current_user
)
```

### Loading with Boundaries

```elixir
# Load only permitted objects
permitted_objects = Bonfire.Boundaries.load_pointers(
  object_ids,
  verbs: [:read],
  current_user: user
)

# Load single object if permitted
object = Bonfire.Boundaries.load_pointer(
  object_id,
  verbs: [:read, :edit],
  current_user: user
)
```

### Query Integration

```elixir
# Add boundaries to Ecto queries
import Bonfire.Boundaries.Queries

query
|> boundarise(main_object.id, current_user: user, verbs: [:read])
|> Repo.all()
```

### Custom ACL Creation

```elixir
# Create ACL with custom grants
{:ok, acl} = Bonfire.Boundaries.Acls.create(
  %{
    named: %{name: "Custom Access"},
    extra_info: %{summary: "Special access rules"}
  },
  current_user: creator
)

# Add grants after creation
Bonfire.Boundaries.Grants.grant(
  friends_circle.id,
  acl.id,
  [:read, :react],
  true,
  current_user: creator
)
```

## Working with Verbs

### Available Verbs

```elixir
# List all verb slugs
Bonfire.Boundaries.Verbs.slugs()
# => [:see, :read, :reply, :edit, :delete, ...]

# Get verb details
verb = Bonfire.Boundaries.Verbs.get(:read)
# => %{id: "4READTHEREC0RDAV01DACCESS1", verb: :read}

# Get verb ID
id = Bonfire.Boundaries.Verbs.get_id!(:edit)
```

### Common Verbs
- `:see` - Discover/list content
- `:read` - View full content
- `:reply` - Comment/respond
- `:react` - Like/boost
- `:edit` - Modify content
- `:delete` - Remove content
- `:request` - Request to follow/join
- `:invite` - Invite others

## Roles System

### Using Predefined Roles

```elixir
# Grant role to circle
Bonfire.Boundaries.Grants.grant_role(
  circle.id,
  acl,
  :interact,  # Can read, reply, react
  true,
  current_user: user
)

# Available roles:
# :administer - Full control
# :contribute - Create and edit
# :participate - Interact fully
# :interact - Read and react
# :read - View only
```

## Best Practices

### Always Check Permissions
```elixir
# ✅ Good
if Bonfire.Boundaries.can?(user, :edit, post) do
  # Allow editing
end

# ❌ Bad - No permission check
# Allow editing directly
```

### Use Appropriate Scopes
```elixir
# ✅ Good - User-level block
Bonfire.Boundaries.Blocks.block(user, :silence, current_user: blocker)

# ✅ Good - Admin instance-wide block
if Bonfire.Boundaries.can?(admin, :block, :instance) do
  Bonfire.Boundaries.Blocks.block(user, :silence, :instance_wide)
end
```

### Handle Permission Errors
```elixir
# ✅ Good
case Bonfire.Boundaries.load_pointer(id, current_user: user, verbs: [:read]) do
  nil -> {:error, :not_found_or_no_permission}
  object -> {:ok, object}
end

# ❌ Bad - Assumes permission
Needle.get!(id)
```

## Integration with Other Extensions

### With Posts
```elixir
# Publish with boundaries
{:ok, post} = Bonfire.Posts.publish(
  current_user: author,
  boundary: "public",  # or acl.id
  post_attrs: %{post_content: %{name: "Title"}}
)
```

### With Social Graph
```elixir
# Follow requests respect boundaries
{:ok, request} = Bonfire.Social.Graph.Follows.follow(
  follower,
  followed,
  current_user: follower
)
```

### With Feeds
```elixir
# Feeds automatically filter by boundaries
activities = Bonfire.Social.FeedActivities.feed(
  :local,
  current_user: viewer
)
```

## Anti-Patterns to Avoid

### ❌ Bypassing Boundaries
```elixir
# Bad - Direct database access
Repo.get(Post, id)

# Good - Use boundary-aware loading
Bonfire.Boundaries.load_pointer(id, current_user: user, verbs: [:read])
```

### ❌ Hardcoding Permissions
```elixir
# Bad - Assumes user can always edit their content
if post.creator_id == user.id, do: allow_edit()

# Good - Check actual permissions
if Bonfire.Boundaries.can?(user, :edit, post), do: allow_edit()
```

### ❌ Ignoring Permission Precedence
```elixir
# Bad - Only checks for allows
has_permission = Enum.any?(grants, & &1.value == true)

# Good - Respects deny precedence
# Use built-in functions that handle precedence correctly
Bonfire.Boundaries.can?(user, verb, object)
```

## Troubleshooting

### Debug Permission Issues
```elixir
# Check what boundaries are on an object
boundaries = Bonfire.Boundaries.list_object_boundaries(object)

# Check user's grants on object
grants = Bonfire.Boundaries.users_grants_on(user, object)

# List ACLs on object
acls = Bonfire.Boundaries.list_object_acls(object)
```

### Common Issues

1. **Permission Denied**
   - Check if user is blocked
   - Verify ACLs are properly set on object
   - Ensure grants include required verbs

2. **Queries Return Empty**
   - Add `skip_boundary_check: true` to debug
   - Check if boundaries are being applied
   - Verify current_user is passed correctly

3. **Block Not Working**
   - Blocks are directional (A blocks B ≠ B blocks A)
   - Instance blocks require admin permission
   - Ghost/silence have different effects

## Performance Considerations

- Use `load_pointers` for batch loading with boundaries
- Queries with boundaries use database-level filtering
- Boundary checks are cached during request lifecycle
- Preload `:controlled` association when needed

## Migration and Setup

### Initial Setup for New Users
```elixir
# Automatically creates default circles and ACLs
{:ok, user} = Bonfire.Me.Users.make_account_and_user(params)

# User gets:
# - Personal circles (friends, family, etc.)
# - Default ACLs (public, local, mentions)
# - Proper grants and permissions
```

### Custom Boundary Setup
```elixir
# Create custom boundary system
{:ok, workspace_acl} = Bonfire.Boundaries.Acls.simple_create(admin, "Workspace")
{:ok, team_circle} = Bonfire.Boundaries.Circles.create(admin, %{named: %{name: "Team"}})

# Set up permissions
Bonfire.Boundaries.Grants.grant_role(
  team_circle.id,
  workspace_acl,
  :contribute,
  true,
  current_user: admin
)
```