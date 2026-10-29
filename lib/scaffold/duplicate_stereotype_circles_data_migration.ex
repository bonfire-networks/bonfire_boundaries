defmodule Bonfire.Boundaries.Scaffold.DuplicateStereotypeCirclesDataMigration do
  @moduledoc """
  Merges the duplicate stereotype circles that concurrent jobs made.

  `Circles.get_or_create_stereotype_circle/2` reads, finds none and creates, and nothing keeps the pair of caretaker and stereotype unique, so two jobs for the same new caretaker (a remote instance's `Peer`, a group) each made a circle. The caretaker then had two, and every later call returned `{:error, "Unexpected number of stereotypes"}`.

  Keeps the earliest circle of each caretaker and stereotype, adds the members of the others to it, and deletes the others (their rows go with their pointer).

  Safe to re-run: once merged, `base_query/0` picks up nothing.
  """

  import Ecto.Query
  use Bonfire.Common.Utils
  alias EctoSparkles.DataMigration
  use DataMigration

  # not `repo()`: `use DataMigration` imports `Ecto.Migration`'s, which needs a migration runner
  alias Bonfire.Common.Repo
  alias Bonfire.Data.AccessControl.Encircle
  alias Bonfire.Data.AccessControl.Stereotyped
  alias Bonfire.Data.Identity.Caretaker

  @impl DataMigration
  def base_query do
    # the circles that have an earlier one of the same caretaker and stereotype
    from(c in Caretaker,
      as: :caretaker,
      join: s in Stereotyped,
      as: :stereotyped,
      on: s.id == c.id,
      where:
        exists(
          from(c2 in Caretaker,
            join: s2 in Stereotyped,
            on: s2.id == c2.id,
            where:
              c2.caretaker_id == parent_as(:caretaker).caretaker_id and
                s2.stereotype_id == parent_as(:stereotyped).stereotype_id and
                c2.id < parent_as(:caretaker).id
          )
        ),
      select: %{id: c.id}
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
    Enum.each(results, &safely_merge/1)
  end

  # one at a time, so a circle that fails loses only itself, not the rest of its batch
  defp safely_merge(%{id: duplicate_id}) do
    Repo.transact_with(fn -> merge(duplicate_id) end)
  rescue
    e -> error(e, "could not merge duplicate stereotype circle #{duplicate_id}")
  end

  defp merge(duplicate_id) do
    with {caretaker_id, stereotype_id} <- caretaker_and_stereotype(duplicate_id),
         keeper_id when is_binary(keeper_id) <- earliest_circle(caretaker_id, stereotype_id),
         true <- keeper_id != duplicate_id do
      member_ids =
        Repo.all(from(e in Encircle, where: e.circle_id == ^duplicate_id, select: e.subject_id))

      Repo.insert_all_or_ignore(
        Encircle,
        Enum.map(
          member_ids,
          &%{id: Needle.UID.generate(Encircle), subject_id: &1, circle_id: keeper_id}
        )
      )

      # the circle's mixins, and its memberships, are removed with its pointer
      Repo.delete_all(from(p in Needle.Pointer, where: p.id == ^duplicate_id))

      {:ok, keeper_id}
    else
      _ -> {:ok, nil}
    end
  end

  defp caretaker_and_stereotype(circle_id) do
    Repo.one(
      from(c in Caretaker,
        join: s in Stereotyped,
        on: s.id == c.id,
        where: c.id == ^circle_id,
        select: {c.caretaker_id, s.stereotype_id}
      )
    )
  end

  defp earliest_circle(caretaker_id, stereotype_id) do
    Repo.one(
      from(c in Caretaker,
        join: s in Stereotyped,
        on: s.id == c.id,
        where: c.caretaker_id == ^caretaker_id and s.stereotype_id == ^stereotype_id,
        order_by: [asc: c.id],
        limit: 1,
        select: c.id
      )
    )
  end
end
