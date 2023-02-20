defmodule Bonfire.Boundaries.Stereotyped do
  @moduledoc """
  A marker that identifies special context-dependent semantics to the system.
  """

  use Pointers.Mixin,
    otp_app: :bonfire_boundaries,
    source: "bonfire_boundaries_stereotype"

  alias Bonfire.Boundaries.Stereotyped
  alias Ecto.Changeset
  alias Pointers.Pointer

  mixin_schema do
    belongs_to(:stereotype, Pointer)
  end

  def changeset(stereotype \\ %Stereotyped{}, params) do
    stereotype
    |> Changeset.cast(params, [:id, :stereotype_id])
    |> Changeset.assoc_constraint(:stereotype)
    |> maybe_ignore()
  end

  # if the user didn't provide a stereotype, just ignore the changeset
  defp maybe_ignore(changeset) do
    if Changeset.get_field(changeset, :stereotype_id),
      do: changeset,
      else: Changeset.apply_action(changeset, :ignore)
  end
end

defmodule Bonfire.Boundaries.Stereotyped.Migration do
  @moduledoc false
  use Ecto.Migration
  import Pointers.Migration
  alias Bonfire.Boundaries.Stereotyped

  @stereotype_table Stereotyped.__schema__(:source)

  # create_stereotype_table/{0,1}

  defp make_stereotype_table(exprs) do
    quote do
      require Pointers.Migration

      Pointers.Migration.create_mixin_table Bonfire.Boundaries.Stereotyped do
        Ecto.Migration.add(
          :stereotype_id,
          Pointers.Migration.strong_pointer(),
          null: false
        )

        unquote_splicing(exprs)
      end
    end
  end

  defmacro create_stereotype_table(), do: make_stereotype_table([])

  defmacro create_stereotype_table(do: {_, _, body}),
    do: make_stereotype_table(body)

  # drop_stereotype_table/0

  def drop_stereotype_table(), do: drop_mixin_table(Stereotyped)

  # create_stereotype_stereotype_index/{0, 1}

  defp make_stereotype_stereotype_index(opts) do
    quote do
      Ecto.Migration.create_if_not_exists(
        Ecto.Migration.index(
          unquote(@stereotype_table),
          [:stereotype_id],
          unquote(opts)
        )
      )
    end
  end

  defmacro create_stereotype_stereotype_index(opts \\ [])

  defmacro create_stereotype_stereotype_index(opts),
    do: make_stereotype_stereotype_index(opts)

  def drop_stereotype_stereotype_index(opts \\ []) do
    drop_if_exists(index(@stereotype_table, [:stereotype_id], opts))
  end

  # migrate_stereotype/{0,1}

  defp ms(:up) do
    quote do
      unquote(make_stereotype_table([]))
      unquote(make_stereotype_stereotype_index([]))
    end
  end

  defp ms(:down) do
    quote do
      Bonfire.Boundaries.Stereotyped.Migration.drop_stereotype_stereotype_index()
      Bonfire.Boundaries.Stereotyped.Migration.drop_stereotype_table()
    end
  end

  defmacro migrate_stereotype() do
    quote do
      if Ecto.Migration.direction() == :up,
        do: unquote(ms(:up)),
        else: unquote(ms(:down))
    end
  end

  defmacro migrate_stereotype(dir), do: ms(dir)
end
