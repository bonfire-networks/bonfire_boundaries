defmodule Bonfire.Boundaries.Queries do
  @moduledoc """
  Helpers for writing common boundary-related queries, particularly for applying access control to queries.

  This module provides macros and functions to assist with boundary checks and permission queries.
  """

  # Unfortunately, ecto is against the sort of thing we take for granted in the bonfire ecosystem, so some of these patterns are a bit convoluted to make ecto generate acceptable sql. In particular the lateral join and the macro is a bit loltastic when we could just return an arbitrary tuple if ecto would support inferring (or us providing) the return type of a subquery.

  # import Untangle
  use Bonfire.Common.E
  use Bonfire.Common.Config
  import Untangle
  import Ecto.Query
  alias Bonfire.Common.Types
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
  defmacro boundarise(query \\ nil, field_ref, opts) do
    boundarise_impl(query, field_ref, opts)
  end

  defp boundarise_impl(query, field_ref, opts) do
    case field_ref do
      {{:., _, [{alia, _, _}, field]}, [{:no_parens, true} | _], []} ->
        boundarise_dot(query, alia, field, opts)

      # Elixir 1.20+ may inject extra metadata (e.g. stop_generated: true) before no_parens
      {{:., _, [{alia, _, _}, field]}, meta, []} when is_list(meta) ->
        if {:no_parens, true} in meta,
          do: boundarise_dot(query, alia, field, opts),
          else:
            raise(RuntimeError,
              message: """
              Invalid field reference: #{inspect(field_ref)}`

              Expected this form:

               * `alias.field` (for ID field `field` on table alias `alias`, e.g: `activity.object_id`)
              """
            )

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

  defp boundarise_dot(query, alia, field, opts) do
    quote do
      require Untangle
      query = unquote(query)
      opts = unquote(opts)
      verbs = List.wrap(e(opts, :verbs, [:see, :read]))

      case Bonfire.Boundaries.Queries.skip_boundary_check?(opts) do
        true ->
          query || Bonfire.Boundaries.Queries.always_true_subquery()

        :admins ->
          agent =
            Common.Utils.current_user_or_id(opts) || Common.Utils.current_account(opts)

          case Bonfire.Me.Accounts.is_admin?(agent) do
            true ->
              Untangle.debug("Skipping boundary checks for instance administrator")

              query || Bonfire.Boundaries.Queries.always_true_subquery()

            _ ->
              Bonfire.Boundaries.Queries.boundarise_query(
                query,
                agent,
                verbs,
                unquote(alia),
                unquote(field),
                opts
              )
          end

        _false ->
          agent =
            Common.Utils.current_user_or_id(opts) || Common.Utils.current_account(opts)

          Bonfire.Boundaries.Queries.boundarise_query(
            query,
            agent,
            verbs,
            unquote(alia),
            unquote(field),
            opts
          )
      end
    end
  end

  @doc """
  Applies the boundary check to `query`, filtering by the parent binding `alia`'s `field`
  (the object id column), using the strategy resolved by `boundarise_strategy/1`. This is
  the shared runtime implementation behind both the `boundarise/3` macro and
  `object_boundarised/2` (the macro only exists to capture the `alias.field` reference).
  """
  def boundarise_query(query, agent, verbs, alia, field, opts) do
    case boundarise_strategy(opts) do
      :direct_exists when not is_nil(query) ->
        pos = permission_probe(agent, verbs, true, alia, field)
        neg = permission_probe(agent, verbs, false, alia, field)

        where(query, [], exists(pos) and not exists(neg))

      strategy ->
        vis =
          query_with_summary(
            agent,
            verbs,
            from(s in base_summary_query(strategy),
              where: s.object_id == field(parent_as(^alia), ^field)
            )
          )

        if query,
          do: where(query, [], exists(vis)),
          else: vis
    end
  end

  def always_true_subquery do
    # NOTE: ugly temp workaround
    from(s in Bonfire.Data.AccessControl.Verb, select: fragment("true"), limit: 1)
  end

  def base_summary_query(strategy \\ :summary_subquery)
  def base_summary_query(:view), do: Summary
  def base_summary_query(_summary_subquery), do: Summary.base_summary_query()

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

  def query_with_summary(user, verbs), do: query_with_summary(user, verbs, base_summary_query())

  def query_with_summary(user, verbs, strategy) when strategy in [:view, :summary_subquery],
    do: query_with_summary(user, verbs, base_summary_query(strategy))

  def query_with_summary(user, verbs, query) do
    subject_ids = user_and_circle_ids(user)
    verbs = Verbs.ids(verbs)

    from(summary in query,
      where:
        summary.subject_id in ^subject_ids and
          summary.verb_id in ^verbs,
      group_by: summary.object_id,
      # `bool_and` (built-in C aggregate) has the same HAVING semantics as our deprecated plpgsql `agg_perms`m SQL aggregates skip NULL inputs, so both compute the AND of the non-null values, and an all-null group yields NULL which fails HAVING either way, but without an interpreted function call per input row (measured ~2× faster over prod-scale grant data)
      having: fragment("bool_and(?)", summary.value),
      select: %{
        subjects: count(summary.subject_id),
        object_id: summary.object_id
      }
    )

    # |> debug()
  end

  # def query_with_summary(user, verbs \\ [:see, :read], query) do
  #   subject_ids = user_and_circle_ids(user)
  #   verbs = Verbs.ids(verbs)

  #   from(summary in query,
  #     where:
  #       summary.subject_id in ^subject_ids and
  #         summary.verb_id in ^verbs,
  #     group_by: summary.object_id,
  #     having: fragment("bool_and(?)", summary.value),
  #     select: %{
  #       subjects: count(summary.subject_id),
  #       object_id: summary.object_id
  #     }
  #   )
  # end

  @doc """
  Queries for all permitted objects for a user.

  ## Examples

      iex> user_id = "user123"
      iex> Bonfire.Boundaries.Queries.permitted_objects(user_id)
  """
  def permitted_objects(user), do: permitted_objects(user, Verbs.slugs())

  @doc """
  Queries for permitted objects for a user with specific verbs.

  ## Examples

      iex> user_id = "user123"
      iex> Bonfire.Boundaries.Queries.permitted_objects(user_id, [:read, :write])
  """
  def permitted_objects(user, verbs) do
    subject_ids = user_and_circle_ids(user)
    verbs = Verbs.ids(verbs)

    from(summary in Summary,
      where: summary.subject_id in ^subject_ids,
      where: summary.verb_id in ^verbs,
      group_by: [summary.object_id],
      having: fragment("bool_and(?)", summary.value),
      select: %{
        subjects: count(summary.subject_id),
        object_id: summary.object_id,
        verbs: fragment("array_agg(?)", summary.verb_id)
      }
    )
  end

  @doc """
  Base query for the grants a subject holds on some objects.
  """
  def query_users_grants_on(subject, things, verbs \\ nil) do
    query_grants_on(things, verbs)
    |> where([s], s.subject_id in ^user_and_circle_ids(subject))
  end

  @doc """
  Base query for every grant held on some objects, by any subject.

  See `query_users_grants_on/3` for the variant scoped to one subject.
  """
  def query_grants_on(things, verbs \\ nil) do
    from(s in Summary,
      where: s.object_id in ^Types.uids(things)
    )
    |> maybe_only_verbs(verbs)
  end

  @doc """
  Returns which of the given verbs a subject may perform on one object, as verb slugs.

  Grouping by verb rather than by object is the whole point: `permitted_objects/2` groups by object, so `bool_and` there means "permitted for ALL the verbs asked about" and one denied verb drops the object entirely. Here each verb is judged on its own grant rows, so asking about `[:follow, :request]` can answer "not follow, but yes request" — which is what a caller needs to tell "you may not follow" from "you may not even ask".

  Negative precedence stays in SQL (`bool_and` over the verb's rows, so any `false` grant wins) and subjects are expanded with `user_and_circle_ids/1`, so grants held by the `local` / `activity_pub` / `guest` circles count. Both are easy to get wrong when reimplementing this over `Bonfire.Boundaries.users_grants_on/2`.

  ## Examples

      iex> Bonfire.Boundaries.Queries.permitted_verbs_on(user, object, [:follow, :request])
      [:request]
  """
  def permitted_verbs_on(subject, object, verbs \\ nil) do
    subject_ids = user_and_circle_ids(subject)

    from(summary in Summary,
      where: summary.subject_id in ^subject_ids,
      where: summary.object_id == ^Types.uid(object),
      group_by: [summary.verb_id],
      having: fragment("bool_and(?)", summary.value),
      select: summary.verb_id
    )
    |> maybe_only_verbs(verbs)
    |> Bonfire.Common.Repo.all()
    |> Enum.map(&Verbs.get_slug/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Narrows a `Summary` query to the given verbs, or leaves it alone when none are given."
  def maybe_only_verbs(query, verbs) when is_nil(verbs) or verbs == [], do: query

  def maybe_only_verbs(query, verbs),
    do: where(query, [summary], summary.verb_id in ^Verbs.ids(verbs))

  @doc """
  Returns the list of subject_ids (e.g. user or circle ids) that have permission for all the given verb_ids on the given object_id.

  ## Examples

      iex> permitted_subjects(["circle1", "circle2"], ["verb1"], "object1")
      ["circle1"]

  """
  def permitted_subjects(subject_ids, verb_ids, object_id) do
    from(summary in Bonfire.Boundaries.Summary,
      where:
        summary.subject_id in ^subject_ids and
          summary.verb_id in ^verb_ids and
          summary.object_id == ^object_id,
      group_by: summary.subject_id,
      having: fragment("bool_and(?)", summary.value),
      select: summary.subject_id
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
  def object_boundarised(q, opts \\ []) do
    boundarise(q, main_object.id, opts)
  end

  @doc """
  Which query strategy `boundarise/3` / `object_boundarised/2` should use:

  - `:summary_subquery` (default) — correlated aggregate over the summary shape (Ecto replica)
  - `:view` — same, over the `bonfire_boundaries_summary` SQL view
  - `:direct_exists` — two correlated index probes: `EXISTS(true grant) AND NOT EXISTS(false grant)`

  Resolution: an explicit `:boundarise_strategy` opt, then the
  `[Bonfire.Boundaries, :boundarise_strategy]` config, then `:summary_subquery`.
  """
  def boundarise_strategy(opts) do
    e(opts, :boundarise_strategy, nil) ||
      Common.Config.get([Bonfire.Boundaries, :boundarise_strategy], :direct_exists)
  end

  @doc """
  A correlated subquery probing for the existence of a grant with the given `value` (`true` = permitting, `false` = denying) matching the parent row's object, the given verbs, and the subject or any circle the subject belongs to. Used in pairs by the `:direct_exists` strategy: `EXISTS(true-probe) AND NOT EXISTS(false-probe)`, which is exactly `HAVING bool_and(value)` decomposed (≥1 true and no false among matched grants), but with pure index lookups instead of a per-row aggregation over the summary shape.
  """
  def permission_probe(subject, verbs, value, parent_alias, parent_field) do
    subject_ids = user_and_circle_ids(subject)
    verb_ids = Verbs.ids(verbs)

    # the subject's circle memberships, resolved as an uncorrelated semi-join: it depends only on query parameters, so the planner evaluates it once per statement against encircle's (subject_id, circle_id) unique index, NOT once per candidate row like the summary shape's `g.subject_id = pointer.id OR encircle...` disjunction, which forced a full encircle scan per row (91% of a measured 17s thread query)
    circle_ids =
      from(e in Bonfire.Data.AccessControl.Encircle,
        where: e.subject_id in ^subject_ids,
        select: e.circle_id
      )

    # NOTE: no named `as:` bindings in here, this runs as a correlated subquery inside arbitrary outer queries, and named bindings could clash with theirs
    from(c in Bonfire.Data.AccessControl.Controlled,
      join: g in Bonfire.Data.AccessControl.Grant,
      on: g.acl_id == c.acl_id,
      where: c.id == field(parent_as(^parent_alias), ^parent_field),
      where: g.verb_id in ^verb_ids,
      where: g.value == ^value,
      where: g.subject_id in ^subject_ids or g.subject_id in subquery(circle_ids),
      select: 1
    )
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

  defp user_and_circle_ids(subject) when is_binary(subject) do
    # a built-in circle used AS the subject (eg. `can?(:activity_pub, ...)`) is its own grant subject: no locality circle applies, and it must not hit the unclassifiable-subject path
    if Bonfire.Boundaries.Circles.is_built_in?(subject),
      do: [subject],
      else: subject_ids_with_locality(subject)
  end

  defp user_and_circle_ids(subject) when is_struct(subject),
    do: subject_ids_with_locality(subject)

  defp user_and_circle_ids(subjects) when is_list(subjects) do
    case subjects do
      [] ->
        [Bonfire.Boundaries.Circles.circles()[:guest][:id]]

      subjects ->
        # each subject classified as it would be on its own, so a batch check sees the same grants a single check would: subjects in one list can differ in locality, so this is a union of their circles rather than one circle for all of them. Each subject still needs `:peered` loaded to be classifiable (see `subject_ids_with_locality/1`)
        subjects
        |> Enum.flat_map(&user_and_circle_ids/1)
        |> Enum.uniq()
    end
  end

  defp user_and_circle_ids(subject) do
    case Types.uids(subject) do
      [] ->
        # no subject at all is a guest, which is a real case rather than a mistake
        [Bonfire.Boundaries.Circles.circles()[:guest][:id]]

      ids when is_list(ids) ->
        # a shape we can't classify without a fetch (an id-only map, say), so least privilege: the subject's own id and no locality circle, which silently narrows what they can see. Same treatment as `subject_ids_with_locality/1` gives an unclassifiable struct, including raising in `:test` to surface the caller
        err(
          subject,
          "Cannot tell this subject's locality without loading it, so no locality circle applies. Pass a struct with `character: [:peered]` loaded"
        )

        ids
    end
  end

  # Picks the locality circle (`:local`/`:activity_pub`) for a single subject. Classifies *without* fetching (`preload_if_needed: false`) so building a boundarised query never triggers a DB round-trip; subjects must arrive with `:peered` already loaded (preloaded at their source, like `Characters.mark_as/2` does for the session user). A subject we cannot classify without a fetch — a bare id, an id-only map, or a struct with `peered: NotLoaded`, fires `Untangle.err` (raising in `:test` to surface the offending caller) and gets no locality circle (least-privilege: just its own id), rather than silently assuming `:local`.
  defp subject_ids_with_locality(subject) do
    case Bonfire.Boundaries.Integration.is_local?(subject,
           preload_if_needed: false,
           on_unclassifiable: :unknown
         ) do
      true -> [Bonfire.Boundaries.Circles.circles()[:local][:id], Types.uid(subject)]
      false -> [Bonfire.Boundaries.Circles.circles()[:activity_pub][:id], Types.uid(subject)]
      _unknown -> [Types.uid(subject)]
    end
  end
end
