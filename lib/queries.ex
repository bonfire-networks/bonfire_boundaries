defmodule Bonfire.Boundaries.Queries do
  @moduledoc """
  Helpers for writing common boundary-related queries, particularly for applying access control to queries.

  This module provides macros and functions to assist with boundary checks and permission queries.
  """

  # Most of this stuff will probably move at some point when we figure
  # out how to better organise it.

  # Unfortunately, ecto is against the sort of thing we take for granted
  # in the bonfire ecosystem, so some of these patterns are a bit
  # convoluted to make ecto generate acceptable sql. In particular the
  # lateral join and the macro is a bit loltastic when we could just
  # return an arbitrary tuple if ecto would support inferring (or us
  # providing) the return type of a subquery.

  # import Untangle
  use Bonfire.Common.E
  import Ecto.Query
  alias Bonfire.Boundaries.Summary
  alias Bonfire.Boundaries.Verbs

  alias Bonfire.Common

  # defmacro can_see?(controlled, user), do: can(controlled, user, :see)
  # defmacro can_edit?(controlled, user), do: can(controlled, user, :edit)
  # defmacro can_delete?(controlled, user), do: can(controlled, user, :delete)
  # defmacro can?(controlled, user, verb \\ :see), do: can(controlled, user, verb)

  defmacro __using__(_) do
    quote do
      import Ecto.Query
      import Bonfire.Boundaries.Queries
    end
  end

  @doc """
  A macro to apply boundary checks to a query.

  ## Examples

      iex> import Bonfire.Boundaries.Queries
      iex> query_visible_posts = from(p in Post)
                                |> boundarise(p.id, current_user: user)

      iex> query_editable_posts = from(p in Post)
                                |> boundarise(p.id, verbs: [:edit], current_user: user)
  """
  defmacro boundarise(query, field_ref, opts) do
    boundarise_impl(query, field_ref, opts)
  end

  defp boundarise_impl(query, field_ref, opts) do
    case field_ref do
      {{:., _, [{alia, _, _}, field]}, [{:no_parens, true} | _], []} ->
        quote do
          require Untangle
          query = unquote(query)
          opts = unquote(opts)
          verbs = List.wrap(e(opts, :verbs, [:see, :read]))

          case Bonfire.Boundaries.Queries.skip_boundary_check?(opts) do
            true ->
              query

            :admins ->
              current_user = Bonfire.Common.Utils.current_user(opts)

              case Bonfire.Me.Accounts.is_admin?(current_user) do
                true ->
                  Untangle.debug("Skipping boundary checks for instance administrator")

                  query

                _ ->
                  vis =
                    Bonfire.Boundaries.Queries.query_with_summary(
                      current_user,
                      verbs,
                      from(Summary, where: [object_id: parent_as(unquote(alia)).unquote(field)])
                    )

                  where(
                    unquote(query),
                    exists(vis)
                  )
              end

            _false ->
              current_user = Bonfire.Common.Utils.current_user(opts)

              # vis = Bonfire.Boundaries.Queries.query_with_summary(uscurrent_userer, verbs)

              # join(
              #   unquote(query),
              #   e(opts, :boundary_join, :inner),
              #   [{unquote(alia), unquote(Macro.var(alia, __MODULE__))}],
              #   v in subquery(vis),
              #   on: unquote(field_ref) == v.object_id
              # )

              vis =
                Bonfire.Boundaries.Queries.query_with_summary(
                  current_user,
                  verbs,
                  from(Summary, where: [object_id: parent_as(unquote(alia)).unquote(field)])
                )

              where(
                unquote(query),
                exists(vis)
              )
          end
        end

      {field, meta, args} = field_ref
      when is_atom(field) and is_list(meta) and
             (is_nil(args) or args == []) ->
        raise RuntimeError,
          message: """
          Specifying only the field name is not supported: #{inspect(field_ref)}`

          Expected this form:

           * `alias.field` (for ID field `field` on table alias `alias`, e.g: `activity.object_id`)
          """

      _ ->
        raise RuntimeError,
          message: """
          Invalid field reference: #{inspect(field_ref)}`

          Expected this form:

           * `alias.field` (for ID field `field` on table alias `alias`, e.g: `activity.object_id`)
          """
    end
  end

  @doc """
  Creates a subquery to filter results based on user permissions.

  Filters out results that the current user is not permitted to perform *all* of the specified verbs on.

  ## Parameters

  - `user`: The current user or their ID
  - `verbs`: A list of verbs to check permissions for (default: [:see, :read])
  - `query`: An initial query on `Summary` to filter objects (optional)

  ## Examples

      iex> user_id = "user123"
      iex> Bonfire.Boundaries.Queries.query_with_summary(user_id, [:read, :write])
  """
  def query_with_summary(user, verbs \\ [:see, :read], query \\ Summary) do
    ids = user_and_circle_ids(user)
    verbs = Verbs.ids(verbs)

    from(summary in query,
      where:
        summary.subject_id in ^ids and
          summary.verb_id in ^verbs,
      group_by: summary.object_id,
      having: fragment("agg_perms(?)", summary.value),
      select: %{
        subjects: count(summary.subject_id),
        object_id: summary.object_id
      }
    )
  end

  @doc """
  Queries for all permitted objects for a user.

  ## Examples

      iex> user_id = "user123"
      iex> Bonfire.Boundaries.Queries.permitted(user_id)
  """
  def permitted(user), do: permitted(user, Verbs.slugs())

  @doc """
  Queries for permitted objects for a user with specific verbs.

  ## Examples

      iex> user_id = "user123"
      iex> Bonfire.Boundaries.Queries.permitted(user_id, [:read, :write])
  """
  def permitted(user, verbs) do
    ids = user_and_circle_ids(user)
    verbs = Verbs.ids(verbs)

    from(summary in Summary,
      where: summary.subject_id in ^ids,
      where: summary.verb_id in ^verbs,
      group_by: [summary.object_id],
      having: fragment("agg_perms(?)", summary.value),
      select: %{
        subjects: count(summary.subject_id),
        object_id: summary.object_id,
        verbs: fragment("array_agg(?)", summary.verb_id)
      }
    )
  end

  @doc """
  A macro that calls the `add_perms(bool?, bool?)` DB function

  ## Examples

      iex> import Bonfire.Boundaries.Queries
      iex> query = from(p in Summary, select: add_perms(p.read, p.write))
  """
  defmacro add_perms(l, r) do
    quote do: Ecto.Query.fragment("add_perms(?,?)", unquote(l), unquote(r))
  end

  @doc """
  A macro that calls the `agg_perms(bool?)` aggregate DB function for combining permissions.

  ## Examples

      iex> import Bonfire.Boundaries.Queries
      iex> query = from(p in Summary, group_by: p.object_id, having: agg_perms(p.value))
  """
  defmacro agg_perms(p) do
    quote do: Ecto.Query.fragment("agg_perms(?)", unquote(p))
  end

  @doc """
  Applies boundary checks to a query for a specific object.

  ## Examples

      iex> query = from(p in Post)
      iex> Bonfire.Boundaries.Queries.object_boundarised(query, current_user: user)
  """
  def object_boundarised(q, opts \\ nil) do
    if Bonfire.Boundaries.Queries.skip_boundary_check?(opts) do
      q
    else
      agent = Common.Utils.current_user(opts) || Common.Utils.current_account(opts)

      vis =
        query_with_summary(
          agent,
          e(opts, :verbs, [:see, :read]),
          from(Summary, where: [object_id: parent_as(:main_object).id])
        )

      where(
        q,
        [main_object: main_object],
        exists(vis)
      )
    end
  end

  @doc """
  Checks if boundary checks should be skipped based on the provided options and object.

  ## Examples

      iex> Bonfire.Boundaries.Queries.skip_boundary_check?([skip_boundary_check: true])
      true

      iex> Bonfire.Boundaries.Queries.skip_boundary_check?([], %{id: "user123"})
      false

      iex> Bonfire.Boundaries.Queries.skip_boundary_check?([current_user: %{id: "user123"}], %{id: "user123"})
      true
  """
  def skip_boundary_check?(opts, object \\ nil) do
    (Common.Config.env() != :prod and
       Common.Config.get(:skip_all_boundary_checks)) ||
      (not is_nil(object) and
         (Common.Enums.id(object) == Common.Utils.current_user_id(opts) ||
            Common.Enums.id(object) == Common.Utils.current_account_id(opts))) ||
      (is_list(opts) and Keyword.get(opts, :skip_boundary_check))
  end

  defp user_and_circle_ids(subjects) do
    case Bonfire.Common.Types.uids(subjects) do
      [] -> [Bonfire.Boundaries.Circles.circles()[:guest][:id]]
      ids when is_list(ids) -> ids
    end
  end
end
