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
  require Logger

  @doc """
  A subquery to join to which filters out results the current user is
  not permitted to see.

  Parameters are the alias for the controlled item in the parent
  query and an expression evaluating to the current user.

  Currently requires a lateral join, but this shouldn't be necessary
  once we've figured out how to make ecto support what we do better.
  """
  defmacro can_see?(controlled, user), do: can(controlled, user, :see)

  defmacro can_read?(controlled, user), do: can(controlled, user, :read)

  defmacro can_edit?(controlled, user), do: can(controlled, user, :edit)

  defmacro can_delete?(controlled, user), do: can(controlled, user, :delete)

  defmacro can?(controlled, user, verb \\ :see), do: can(controlled, user, verb)

  defp can({controlled, _, _}, user, verb), do: can(controlled, user, verb)
  defp can({controlled_schema, controlled_id}, user, verb), do: can(controlled_schema, user, verb, controlled_id)
  defp can(controlled_schema, user, verb, controlled_id \\ :id) when is_atom(controlled_schema) do
    admins = Bonfire.Boundaries.Circles.circles()[:admin]
    guests = Bonfire.Boundaries.Circles.circles()[:guest]
    quote do
      require Logger
      require Ecto.Query
      require Bonfire.Boundaries.Queries
      verb_ids = Bonfire.Boundaries.Verbs.ids(unquote(verb))
      case unquote(user) do
        %{id: user_id, instance_admin: %{is_instance_admin: true}} ->
          Logger.debug("Boundaries: query as admin and #{user_id}")
          unquote(user_can(verb, controlled_schema, controlled_id, [guests, admins]))
        %{id: user_id} ->
          Logger.debug("Boundaries: query as user #{user_id}")
          unquote(user_can(verb, controlled_schema, controlled_id, [guests]))
        user_id when is_binary(user_id) ->
          Logger.debug("Boundaries: query as user_id #{user_id}")
          unquote(user_can(verb, controlled_schema, controlled_id, [guests]))
        _ ->
          Logger.debug("Boundaries: query as guest")
          unquote(guest_can(verb, controlled_schema, controlled_id))
      end
      |> Ecto.Query.subquery()
    end
  end

  defp controlled_query(args) do
    quote do
      Ecto.Query.from(controlled in Bonfire.Data.AccessControl.Controlled, unquote(args))
    end
  end

  defp can_join_where(verb, controlled_schema, controlled_id) when verb in [:see, :read] or verb == [:see, :read] or verb == [:read, :see] do
    quote do: [
      join: acl in assoc(controlled, :acl),
      join: grant in assoc(acl, :grants),
      join: access in assoc(grant, :access),
      left_join: circle in Bonfire.Data.Social.Circle,
      on: grant.subject_id == circle.id,
      where: controlled.id == field(parent_as(unquote(controlled_schema)), unquote(controlled_id)),
      group_by: [controlled.id, access.id],
      having: fragment("agg_perms(?)", access.can_see),
      select: %{struct(access, [:id]) | can_see: fragment("agg_perms(?)", access.can_see), can_read: fragment("agg_perms(?)", access.can_read)}
    ]
  end

  defp can_join_where(_verb, controlled_schema, controlled_id) do
    quote do: [
      join: acl in assoc(controlled, :acl),
      join: grant in assoc(acl, :grants),
      join: access in assoc(grant, :access),
      join: interact in assoc(access, :interacts),
      left_join: circle in Bonfire.Data.Social.Circle,
      on: grant.subject_id == circle.id,
      where: interact.verb_id in ^verb_ids,
      where: controlled.id == field(parent_as(unquote(controlled_schema)), unquote(controlled_id)),
      group_by: [controlled.id, interact.id],
      having: fragment("agg_perms(?)", interact.value),
      select: struct(interact, [:id])
    ]
  end

  defp guest_where() do
    quote do: [ where: circle.id == ^Bonfire.Boundaries.Circles.circles()[:guest] ]
  end

  defp user_where(circles) do
    quote do
      [
        left_join: encircle in assoc(circle, :encircles),
        where: circle.id in ^unquote(circles) or grant.subject_id == ^user_id or encircle.subject_id == ^user_id,
      ]
    end
  end

  #doc "Checks if a guest (i.e. anyone) can X"

  defp guest_can(verb, controlled_schema, controlled_id) do
    controlled_query(can_join_where(verb, controlled_schema, controlled_id) ++ guest_where())
  end

  defp user_can(verb, controlled_schema, controlled_id, circles) do
    controlled_query(can_join_where(verb, controlled_schema, controlled_id) ++ user_where(circles))
  end

  @doc "Call the `add_perms(bool?, bool?)` postgres function for combining permissions."
  defmacro add_perms(l, r) do
    quote do: Ecto.Query.fragment("add_perms(?,?)", unquote(l), unquote(r))
  end

  @doc "Call the `agg_perms(bool?)` postgres aggregate for combining permissions."
  defmacro agg_perms(p) do
    quote do: Ecto.Query.fragment("agg_perms(?)", unquote(p))
  end

  @doc """
  FIXME
  Lists permitted interactions on something for the current user.

  Parameters are the alias for the controlled item in the parent
  query and an expression evaluating to the current user.

  Currently requires a left lateral join. The final version may or may
  not, depending on how it is used.

  Does not recognise admins correctly right now, they're treated as regular users.
  """
  def permitted_on(controlled_schema, user)
  def permitted_on({controlled_schema, controlled_id}, user), do: permitted_on(controlled_schema, user, controlled_id)
  def permitted_on(controlled_schema, user), do: permitted_on(controlled_schema, user, :id)

  defp permitted_on(controlled_schema, user, controlled_id) do
    local = Bonfire.Boundaries.Circles.circles()[:local]
    guest = Bonfire.Boundaries.Circles.circles()[:guest]

    quote do
      require Ecto.Query

      users = case unquote(user) do
        %{id: id} -> [id, unquote(local)]
        _ -> [unquote(guest)]
      end

    Ecto.Query.from controlled on Bonfire.Data.AccessControl.Controlled,
        join: acl in assoc(controlled, :acl),
        join: grant in assoc(acl, :grants),
        join: access in assoc(grant, :access),
        join: interact in assoc(access, :interacts),
        left_join: circle in Bonfire.Data.Social.Circle,
        on: grant.subject_id == circle.id,
        left_join: encircle in assoc(circle, :encircles),
        where: grant.subject_id in ^users or encircle.subject_id in ^users,
        where: controlled.id == field(parent_as(unquote(controlled_schema)), unquote(controlled_id)),
        group_by: [controlled.id, interact.verb_id],
        having: Bonfire.Boundaries.Queries.agg_perms(interact.value),
        select: struct(interact, [:id, :verb_id])
    end
  end

   def object_only_visible_for(q, opts_or_user_or_conn_or_socket \\ nil) do
      user = Bonfire.Common.Utils.current_user(opts_or_user_or_conn_or_socket)
      cs = can_see?(:main_object, user)

      q
      |> Ecto.Query.join(:left_lateral, [], cs in ^cs, as: :cs)
      |> Ecto.Query.where([cs: cs], cs.can_see == true)
  end

end
