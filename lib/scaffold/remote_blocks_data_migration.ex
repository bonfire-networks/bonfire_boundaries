defmodule Bonfire.Boundaries.Scaffold.RemoteBlocksDataMigration do
  @moduledoc """
  Makes the blocks that remote actors sent before their blocks denied anything take effect.

  A remote actor is scaffolded with a `ghost_them` circle but no ACL reading it (`:remote_user_boundaries`), so an incoming `Block` put one of our users in that circle and stopped nothing: they could still see and reply to the blocker's posts here. The ACL is now created the first time a remote actor blocks someone (`Bonfire.Boundaries.Blocks`), and this does the same for those who blocked someone already: it creates their ghost ACL and attaches it to their posts here, through `Bonfire.Boundaries.Scaffold.create_missing_block_boundaries/2`.

  Safe to re-run: someone put right has the ACL, so `base_query/0` no longer picks them up.
  """

  import Ecto.Query
  use Bonfire.Common.Utils
  alias EctoSparkles.DataMigration
  use DataMigration

  alias Bonfire.Data.AccessControl.Encircle
  alias Bonfire.Data.AccessControl.Stereotyped
  alias Bonfire.Data.Identity.Caretaker

  @impl DataMigration
  def base_query do
    ghost_circle = Bonfire.Boundaries.Circles.get_id!(:ghost_them)
    ghost_acl = Bonfire.Boundaries.Acls.get_id!(:ghosted_cannot_anything)

    # remote actors, with someone in their `ghost_them` circle, and no ghost ACL
    from(u in Bonfire.Data.Identity.User,
      as: :user,
      join: p in Bonfire.Data.ActivityPub.Peered,
      on: p.id == u.id,
      where:
        exists(
          from(c in Caretaker,
            join: s in Stereotyped,
            on: s.id == c.id and s.stereotype_id == ^ghost_circle,
            join: e in Encircle,
            on: e.circle_id == c.id,
            where: c.caretaker_id == parent_as(:user).id
          )
        ) and
          not exists(
            from(c in Caretaker,
              join: s in Stereotyped,
              on: s.id == c.id and s.stereotype_id == ^ghost_acl,
              where: c.caretaker_id == parent_as(:user).id
            )
          ),
      select: %{id: u.id}
    )
  end

  @impl DataMigration
  def config do
    %DataMigration.Config{
      # do not block app startup in auto-migrations
      async: true,
      batch_size: 100,
      throttle_ms: 1_000,
      repo: Bonfire.Common.Repo,
      first_id: "00000000000000000000000000"
    }
  end

  @impl DataMigration
  def migrate(results) do
    Enum.each(results, &safely_scaffold/1)
  end

  # one at a time, so an actor that fails loses only themselves, not the rest of their batch
  defp safely_scaffold(%{id: _} = actor) do
    Bonfire.Boundaries.Scaffold.create_missing_block_boundaries(actor, [:ghost_them])
  rescue
    e ->
      error(e, "Could not apply the blocks of #{inspect(actor)}, going on with the next")
  catch
    kind, reason ->
      error(
        {kind, reason},
        "Could not apply the blocks of #{inspect(actor)}, going on with the next"
      )
  end
end
