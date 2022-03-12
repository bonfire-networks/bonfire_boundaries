defmodule Bonfire.Boundaries.Queries do
  @moduledoc """
  Helpers for writing common queries. In particular, access control.

  Most of this stuff will probably move at some point when we figure
  out how to better organise it.

  Unfortunately, ecto is against the sort of thing we take for granted
  in the bonfire ecosystem, so some of these patterns are a bit
  convoluted to make ecto generate acceptable sql. In particular the
  lateral join and the macro is a bit loltastic when we could just
  return an arbitrary tuple if ecto would support inferring (or us
  providing) the return type of a subquery.

  """
  import Where
  import Ecto.Query
  alias Bonfire.Boundaries.{Summary, Verbs}
  alias Bonfire.Common

  # defmacro can_see?(controlled, user), do: can(controlled, user, :see)

  # defmacro can_edit?(controlled, user), do: can(controlled, user, :edit)

  # defmacro can_delete?(controlled, user), do: can(controlled, user, :delete)

  # defmacro can?(controlled, user, verb \\ :see), do: can(controlled, user, verb)

  def user_and_circle_ids(user) do
    case user do
      %{id: user_id} -> [user_id]
      _ when is_binary(user) -> [user]
      _ -> [Bonfire.Boundaries.Circles.circles()[:guest][:id]]
    end
  end

  defmacro boundarise(query, field_ref, opts),
    do: boundarise_impl(query, field_ref, opts)

  defp boundarise_impl(query, field_ref, opts) do
    case field_ref do
      {{:., _, [{alia, _, _},field]}, [{:no_parens, true}|_], []} ->
        quote do
          require Where
          query = unquote(query)
          opts = unquote(opts)
          verbs = Bonfire.Common.Utils.e(opts, :verbs, [:see, :read])
          case Bonfire.Boundaries.Queries.skip_boundary_check?(opts) do
            true -> query
            :admins ->
              case Bonfire.Common.Utils.current_user(opts) do
                %{id: _, instance_admin: %{is_instance_admin: true}} ->
                  Where.debug("Skipping boundary checks for instance administrator")
                  query
                current_user ->
                  vis = Bonfire.Boundaries.Queries.filter_where_not(current_user, verbs)
                  join unquote(query), :inner,
                    [{unquote(alia), unquote(Macro.var(alia, __MODULE__))}],
                    v in subquery(vis), on: unquote(field_ref) == v.object_id
              end
            false ->
              user = Bonfire.Common.Utils.current_user(opts)
              vis = Bonfire.Boundaries.Queries.filter_where_not(user, verbs)
              join unquote(query), :inner,
                [{unquote(alia), unquote(Macro.var(alia, __MODULE__))}],
                v in subquery(vis), on: unquote(field_ref) == v.object_id
            other ->
              import Where
              debug(other, "Weird skip_boundary_check")
              query
          end
        end
      {field, [{:no_parens, true}|_], []}=field_ref when is_atom(field) ->
        quote do
          require Where
          query = unquote(query)
          opts = unquote(opts)
          verbs = Bonfire.Common.Utils.e(opts, :verbs, [:see, :read])
          case Bonfire.Boundaries.Queries.skip_boundary_check?(opts) do
            true -> query
            :admins ->
              case Bonfire.Common.Utils.current_user(opts) do
                %{id: _, instance_admin: %{is_instance_admin: true}} ->
                  Where.debug("Skipping boundary checks for instance administrator")
                  query
                current_user ->
                  vis = Bonfire.Boundaries.Queries.filter_where_not(current_user, verbs)
                  join unquote(query), :inner,
                    [unquote(Macro.var(:root, __MODULE__))],
                    v in subquery(vis),
                    on: unquote(Macro.var(:root, __MODULE__)).unquote(field_ref) == v.object_id
              end
            false ->
              user = Bonfire.Common.Utils.current_user(opts)
              vis = Bonfire.Boundaries.Queries.filter_where_not(user, verbs)
              join unquote(query), :inner,
                [unquote(Macro.var(:root, __MODULE__))],
                v in subquery(vis),
                on: unquote(Macro.var(:root, __MODULE__)).unquote(field_ref) == v.object_id
            other ->
              import Where
              debug(other, "Weird skip_boundary_check")
              query
          end
        end
      _ ->
        raise RuntimeError,
          message: """
          Invalid field reference: #{inspect(field_ref)}`

          Expected one of these forms:

           * `field` (for field `field` on the root schema)
           * `alias.field` (for field `field` on alias `alias
          """
    end
  end

  @doc """
  A subquery which filters out results the current user is
  not permitted to perform *all* of the verbs on.

  Parameters are the alias for the controlled item in the parent
  query and an expression evaluating to the current user.
  """
  def filter_where_not(user, verbs \\ [:see, :read]) do
    ids = user_and_circle_ids(user)
    verbs = Verbs.ids(verbs)
    from summary in Summary,
      where: summary.subject_id in ^ids,
      where: summary.verb_id in ^verbs,
      group_by: summary.object_id,
      having: fragment("agg_perms(?)", summary.value),
      select: %{
        subjects: count(summary.subject_id),
        object_id: summary.object_id,
      }
  end

  def permitted(user), do: permitted(user, Verbs.slugs())
  def permitted(user, verbs) do
    ids = user_and_circle_ids(user)
    verbs = Verbs.ids(verbs)
    from summary in Summary,
      where: summary.subject_id in ^ids,
      where: summary.verb_id in ^verbs,
      group_by: [summary.object_id],
      having: fragment("agg_perms(?)", summary.value),
      select: %{
        subjects: count(summary.subject_id),
        object_id: summary.object_id,
        verbs: fragment("array_agg(?)", summary.verb_id)
      }
  end

  @doc "Call the `add_perms(bool?, bool?)` postgres function for combining permissions."
  defmacro add_perms(l, r) do
    quote do: Ecto.Query.fragment("add_perms(?,?)", unquote(l), unquote(r))
  end

  @doc "Call the `agg_perms(bool?)` postgres aggregate for combining permissions."
  defmacro agg_perms(p) do
    quote do: Ecto.Query.fragment("agg_perms(?)", unquote(p))
  end

  def object_boundarised(q, opts \\ nil) do
    if Bonfire.Boundaries.Queries.skip_boundary_check?(opts) do
      q
    else
      agent = Bonfire.Common.Utils.current_user(opts) || Bonfire.Common.Utils.current_account(opts)

      vis = filter_where_not(agent, Common.Utils.e(opts, :verbs, [:see, :read]))
      join q, :inner, [main_object: main_object],
        v in subquery(vis),
        on: main_object.id == v.object_id
    end
  end

  def skip_boundary_check?(opts) do
    (Common.Config.get(:env) != :prod && Common.Config.get(:skip_all_boundary_checks))
    || is_list(opts) && Keyword.get(opts, :skip_boundary_check, false)
  end

end
