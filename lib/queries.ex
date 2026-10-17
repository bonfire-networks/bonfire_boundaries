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

      case Bonfire.Boundaries.Queries.verbs_from_opts(opts) do
        # an unresolvable verb option fails closed rather than falling back to a weaker check
        {:error, _} ->
          Bonfire.Boundaries.Queries.deny_all(query)

        {:ok, verbs} ->
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
        where(query, ^direct_exists_permitted(agent, verbs, alia, field))

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

  # The `:direct_exists` condition. All the verbs: a grant of each, and no denial of any, so one probe per verb plus one (a single verb, as listing by `:see` is, keeps the two probes it always had). `{:any, verbs}`: each verb judged on its own, granted and not denied, any one passing
  defp direct_exists_permitted(agent, {:any, verbs}, alia, field) do
    verbs
    |> List.wrap()
    |> Enum.uniq()
    |> Enum.reduce(dynamic(false), fn verb, acc ->
      pos = permission_probe(agent, [verb], true, alia, field)
      neg = permission_probe(agent, [verb], false, alia, field)
      dynamic(^acc or (exists(pos) and not exists(neg)))
    end)
  end

  defp direct_exists_permitted(agent, verbs, alia, field) do
    neg = permission_probe(agent, verbs, false, alia, field)

    verbs
    |> List.wrap()
    |> Enum.uniq()
    |> Enum.reduce(dynamic(not exists(neg)), fn verb, acc ->
      pos = permission_probe(agent, [verb], true, alia, field)
      dynamic(^acc and exists(pos))
    end)
  end

  def always_true_subquery do
    # NOTE: ugly temp workaround
    from(s in Bonfire.Data.AccessControl.Verb, select: fragment("true"), limit: 1)
  end

  @doc """
  The verbs a boundary query checks, read from `opts`.

  The option is `verbs:`: a list, which means ALL of them, or `{:any, list}`, which means at least one. It defaults to `[:see]`, which is whether something may be LISTED (feeds, threads, listings); opening one object by its link asks for `[:read]`, and showing its content to whoever finds it (public search) `[:see, :read]`. A singular `verb:` is taken as `verbs: [verb]` but still errors, so its callers move to `verbs:`: it used to be ignored, which silently checked only the default. Both at once is refused, since quietly picking one would hide the mistake.

  `err/2` raises in dev and test, and only logs in production.
  """
  def verbs_from_opts(opts) do
    case {e(opts, :verbs, nil), e(opts, :verb, nil)} do
      {nil, nil} ->
        {:ok, [:see]}

      {{:any, verbs}, nil} ->
        {:ok, {:any, List.wrap(verbs)}}

      {verbs, nil} ->
        {:ok, List.wrap(verbs)}

      {nil, verb} ->
        err(verb, "Please pass a list of `verbs`, not a `verb` (singular) in opts")
        {:ok, List.wrap(verb)}

      {verbs, verb} ->
        error(
          {verbs, verb},
          "Boundaries were given both `verbs:` and `verb:`, so refusing rather than widen or guess"
        )
    end
  end

  @doc "Fails a boundary check closed: the query matches nothing."
  def deny_all(nil),
    do: from(s in Bonfire.Data.AccessControl.Verb, select: fragment("true"), where: false)

  def deny_all(query), do: where(query, [], false)

  def base_summary_query(strategy \\ :summary_subquery)
  def base_summary_query(:view), do: Summary
  def base_summary_query(_summary_subquery), do: Summary.base_summary_query()

  @doc """
  Creates a subquery to filter results based on user permissions.

  Keeps the objects the user may do ALL of these verbs on (a grant of each, a denial of none), or with `{:any, verbs}` at least one of them (each verb judged on its own).

  ## Parameters

  - `user`: The current user or their ID
  - `verbs`: A list of verbs, or `{:any, verbs}`
  - `query`: An initial query on `Summary` to filter objects (optional)

  ## Examples

      iex> user_id = "user123"
      iex> Bonfire.Boundaries.Queries.query_with_summary(user_id, [:read, :write])
  """

  def query_with_summary(user, verbs), do: query_with_summary(user, verbs, base_summary_query())

  def query_with_summary(user, verbs, strategy) when strategy in [:view, :summary_subquery],
    do: query_with_summary(user, verbs, base_summary_query(strategy))

  def query_with_summary(user, {:any, verbs}, query) do
    subject_ids = user_and_circle_ids(user)
    verbs = Verbs.ids(verbs)

    # grouped by object AND verb, so each verb passes or fails on its own rows, and the object is kept for any that passes
    from(summary in query,
      where:
        summary.subject_id in ^subject_ids and
          summary.verb_id in ^verbs,
      group_by: [summary.object_id, summary.verb_id],
      having: fragment("bool_and(?)", summary.value),
      select: %{
        subjects: count(summary.subject_id),
        object_id: summary.object_id
      }
    )
  end

  def query_with_summary(user, verbs, query) do
    subject_ids = user_and_circle_ids(user)
    verbs = Verbs.ids(verbs) |> Enum.uniq()

    from(summary in query,
      where:
        summary.subject_id in ^subject_ids and
          summary.verb_id in ^verbs,
      group_by: summary.object_id,
      # `bool_and` (built-in C aggregate) has the same HAVING semantics as our deprecated plpgsql `agg_perms`m SQL aggregates skip NULL inputs, so both compute the AND of the non-null values, and an all-null group yields NULL which fails HAVING either way, but without an interpreted function call per input row (measured ~2× faster over prod-scale grant data). It refuses any denial; the count requires a GRANT of every verb, since a verb with no row, or only an undecided (null) one, is not granted
      having:
        fragment("bool_and(?)", summary.value) and
          fragment("count(distinct ?) filter (where ?)", summary.verb_id, summary.value) ==
            ^length(verbs),
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
  Which of these subjects (eg. circles) may do every one of these verbs on one object, each answering for itself alone: a grant to a circle counts for that circle, with no locality circle pooled in. A denial wins. Returns their ids.

  ## Examples

      iex> permitted_subjects(["circle1", "circle2"], ["verb1"], "object1")
      ["circle1"]

  """
  def permitted_subjects(subject_ids, verbs, object_id) do
    subject_ids
    |> Enum.map(&%{for_id: &1, subject_id: &1})
    |> permitted_for(verbs, object_id)
  end

  @doc """
  Which of these users may do every one of these verbs on one object, each answered as a check of them alone would be: their own grants pooled with their locality circle's (`user_and_circle_ids/1`), and a denial winning. Returns the users' ids.

  ## Examples

      iex> permitted_users([bob, carol], [:see, :read], object_id) |> repo().all()
      [bob_id]
  """
  def permitted_users(users, verbs, object_id) do
    for(
      user <- List.wrap(users),
      subject_id <- user_and_circle_ids(user),
      do: %{for_id: Types.uid(user), subject_id: subject_id}
    )
    |> permitted_for(verbs, object_id)
  end

  # One query for any number of askers: each is paired with the subjects whose grants count for them (themselves, and for a user their locality circle), and the summary rows are grouped by asker. Nobody asking is answered by nobody, as `values/2` takes no empty list
  defp permitted_for([], _verbs, _object_id), do: deny_all(nil)

  defp permitted_for(pairs, verbs, object_id) do
    verb_ids = Verbs.ids(verbs) |> Enum.uniq()
    id_type = Summary.__schema__(:type, :subject_id)
    subject_ids = pairs |> Enum.map(& &1.subject_id) |> Enum.uniq()

    from(pair in values(pairs, %{for_id: id_type, subject_id: id_type}),
      join: summary in Summary,
      on: summary.subject_id == pair.subject_id,
      # the subjects as a literal list too, as `query_with_summary/3` gives them: the view has a row per pointer as subject, and only a list Postgres can see lets it narrow those before building rows. The join to `VALUES` alone isn't pushed into the view, so it built rows for every pointer first, timing out for ONE recipient on prod (17 October)
      where:
        summary.subject_id in ^subject_ids and summary.object_id == ^object_id and
          summary.verb_id in ^verb_ids,
      group_by: pair.for_id,
      # `bool_and` refuses any denial; the count requires a GRANT of every verb, since a verb with no row, or only an undecided (null) one, is not granted
      having:
        fragment("bool_and(?)", summary.value) and
          fragment("count(distinct ?) filter (where ?)", summary.verb_id, summary.value) ==
            ^length(verb_ids),
      select: pair.for_id
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
    verb_ids = Verbs.ids(verbs)

    # NOTE: no named `as:` bindings in here, this runs as a correlated subquery inside arbitrary outer queries, and named bindings could clash with theirs
    from(c in Bonfire.Data.AccessControl.Controlled,
      join: g in Bonfire.Data.AccessControl.Grant,
      on: g.acl_id == c.acl_id,
      where: c.id == field(parent_as(^parent_alias), ^parent_field),
      where: g.verb_id in ^verb_ids,
      where: g.value == ^value,
      select: 1
    )
    |> where_granted_to(subject)
  end

  @doc """
  The verbs the subject may do on each of these objects, as `{object_id, verb_id}` pairs: granted to them or a circle they are in, and denied to neither, judged per verb (`bool_and`). One query for any number of objects, straight from the grants as `permission_probe/5` reads them rather than through the summary view, which for a page of a feed was ~20× slower (483ms against 23ms, measured on prod 16 October).

  `Bonfire.Boundaries.boundaries_on_objects/3` loads a feed page's boundaries with it. A subject of `nil` is a guest.
  """
  def granted_verbs_on(subject, object_ids) do
    from(c in Bonfire.Data.AccessControl.Controlled,
      join: g in Bonfire.Data.AccessControl.Grant,
      on: g.acl_id == c.acl_id,
      where: c.id in ^Types.uids(object_ids),
      group_by: [c.id, g.verb_id],
      having: fragment("bool_and(?)", g.value),
      select: {c.id, g.verb_id}
    )
    |> where_granted_to(subject)
  end

  @doc """
  The same pairs as `granted_verbs_on/2`, judged once per ACL rather than once per object and ACL: objects mostly share preset ACLs, so a feed page's 20 posts reach ~230 ACL attachments but few distinct ACLs, and the per-object query looked the same grants up again for each (229 lookups, 65-74ms of a page on prod, 17 October). Each distinct ACL's grants to the subject are reduced to `bool_and` per verb once, then per object across its ACLs, which is the same rule (a denial on any of its ACLs wins), so the two must agree.

  `Bonfire.Boundaries.boundaries_on_objects/3` uses this one, unless `config :bonfire_boundaries, Bonfire.Boundaries, granted_verbs_strategy: :per_object` says otherwise, kept so the two can be compared on a live instance.
  """
  def granted_verbs_on_per_acl(subject, object_ids) do
    object_ids = Types.uids(object_ids)

    acl_ids =
      from(c in Bonfire.Data.AccessControl.Controlled,
        where: c.id in ^object_ids,
        distinct: true,
        select: %{acl_id: c.acl_id}
      )

    # grouped, so the planner computes it once rather than folding it back into a per-object loop
    per_acl =
      from(a in subquery(acl_ids),
        join: g in Bonfire.Data.AccessControl.Grant,
        on: g.acl_id == a.acl_id,
        group_by: [g.acl_id, g.verb_id],
        select: %{acl_id: g.acl_id, verb_id: g.verb_id, granted: fragment("bool_and(?)", g.value)}
      )
      |> where_granted_to(subject)

    from(c in Bonfire.Data.AccessControl.Controlled,
      join: v in subquery(per_acl),
      on: v.acl_id == c.acl_id,
      where: c.id in ^object_ids,
      group_by: [c.id, v.verb_id],
      having: fragment("bool_and(?)", v.granted),
      select: {c.id, v.verb_id}
    )
  end

  @doc "`granted_verbs_on_per_acl/2` or `granted_verbs_on/2`, as configured (`:granted_verbs_strategy`, default `:per_acl`; `:per_object` to compare)."
  def granted_verbs_query(subject, object_ids) do
    case Common.Config.get([Bonfire.Boundaries, :granted_verbs_strategy], :per_acl) do
      :per_object -> granted_verbs_on(subject, object_ids)
      _ -> granted_verbs_on_per_acl(subject, object_ids)
    end
  end

  # Keeps the grants to the subject or any circle they are in, of a query on `Controlled` joined to `Grant` (the second binding).
  # The circle memberships are resolved as an uncorrelated semi-join: it depends only on query parameters, so the planner evaluates it once per statement against encircle's (subject_id, circle_id) unique index, NOT once per candidate row like the summary shape's `g.subject_id = pointer.id OR encircle...` disjunction, which forced a full encircle scan per row (91% of a measured 17s thread query)
  defp where_granted_to(query, subject) do
    subject_ids = user_and_circle_ids(subject)

    circle_ids =
      from(e in Bonfire.Data.AccessControl.Encircle,
        where: e.subject_id in ^subject_ids,
        select: e.circle_id
      )

    # `= ANY(ARRAY(subquery))` rather than `IN (subquery)`, and the difference is the cost model rather than the semantics: both mean "the grant is to some circle this subject is in", and an empty set is false either way. `ARRAY(...)` of an uncorrelated subquery is an InitPlan, costed and run once per statement, while `IN (subquery)` nested inside a correlated EXISTS is costed as part of every probe evaluation. For a viewer in thousands of circles that inflated one probe pair's estimate to ~33M, which swamped every join decision in the outer query and left the winner arbitrary: a sequential scan of millions of `replied` rows, and a notifications page that hit the 15s statement timeout. Same rows, same permissions, 98ms instead
    where(
      query,
      [_c, g],
      g.subject_id in ^subject_ids or
        fragment("? = ANY(ARRAY(?)::uuid[])", g.subject_id, subquery(circle_ids))
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
