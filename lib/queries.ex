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
  import Ecto.Query
  alias Bonfire.Boundaries.SeeRead

  # @doc """
  # A subquery to join to which filters out results the current user is
  # not permitted to see.

  # Parameters are the alias for the controlled item in the parent
  # query and an expression evaluating to the current user.

  # Currently requires a lateral join, but this shouldn't be necessary
  # once we've figured out how to make ecto support what we do better.
  # """
  # defmacro can_see?(controlled, user), do: can(controlled, user, :see)

  # defmacro can_edit?(controlled, user), do: can(controlled, user, :edit)

  # defmacro can_delete?(controlled, user), do: can(controlled, user, :delete)

  # defmacro can?(controlled, user, verb \\ :see), do: can(controlled, user, verb)

  def user_and_circle_ids(user) do
    circles = Bonfire.Boundaries.Circles.circles()
    case user do
      %{id: user_id, instance_admin: %{is_instance_admin: true}} ->
        [user_id, circles[:guest], circles[:local], circles[:admin]]
      # user_id when is_binary(user_id) ->  [user_id, circles[:guest], circles[:local]]
      %{id: user_id} -> [user_id, circles[:guest], circles[:local]]
      _ -> [circles[:guest]]
    end
  end

  def filter_invisible(user) do
    ids = user_and_circle_ids(user)
    from see_read in SeeRead,
      where: see_read.subject_id in ^ids,
      group_by: see_read.object_id,
      having: fragment("add_perms(agg_perms(?), agg_perms(?))", see_read.can_see?, see_read.can_read?),
      select: %{
        subjects: count(see_read.subject_id),
        object_id: see_read.object_id,
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

  # @doc """
  # FIXME
  # Lists permitted interactions on something for the current user.

  # Parameters are the alias for the controlled item in the parent
  # query and an expression evaluating to the current user.

  # Currently requires a left lateral join. The final version may or may
  # not, depending on how it is used.

  # Does not recognise admins correctly right now, they're treated as regular users.
  # """
  # def permitted_on(controlled_schema, user)
  # def permitted_on({controlled_schema, controlled_id}, user), do: permitted_on(controlled_schema, user, controlled_id)
  # def permitted_on(controlled_schema, user), do: permitted_on(controlled_schema, user, :id)

  # defp permitted_on(controlled_schema, user, controlled_id) do
  #   local = Bonfire.Boundaries.Circles.circles()[:local]
  #   guest = Bonfire.Boundaries.Circles.circles()[:guest]

  #   quote do
  #     require Ecto.Query

  #     users = case unquote(user) do
  #       %{id: id} -> [id, unquote(local)]
  #       _ -> [unquote(guest)]
  #     end

  #   Ecto.Query.from controlled on Bonfire.Data.AccessControl.Controlled,
  #       join: acl in assoc(controlled, :acl),
  #       join: grant in assoc(acl, :grants),
  #       join: access in assoc(grant, :access),
  #       join: interact in assoc(access, :interacts),
  #       left_join: circle in Bonfire.Data.AccessControl.Circle,
  #       on: grant.subject_id == circle.id,
  #       left_join: encircle in assoc(circle, :encircles),
  #       where: grant.subject_id in ^users or encircle.subject_id in ^users,
  #       where: controlled.id == field(parent_as(unquote(controlled_schema)), unquote(controlled_id)),
  #       group_by: [controlled.id, interact.verb_id],
  #       having: Bonfire.Boundaries.Queries.agg_perms(interact.value),
  #       select: struct(interact, [:id, :verb_id])
  #   end
  # end

  def object_only_visible_for(q, opts \\ nil) do
    if is_list(opts) and opts[:skip_boundary_check] do
      q
    else
      agent = Bonfire.Common.Utils.current_user(opts) || Bonfire.Common.Utils.current_account(opts)

      vis = filter_invisible(agent)
      join q, :inner, [main_object: main_object],
        v in subquery(vis),
        on: main_object.id == v.object_id
    end
  end

end
