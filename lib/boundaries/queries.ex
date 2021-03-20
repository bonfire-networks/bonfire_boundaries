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
  alias Bonfire.Data.AccessControl.Controlled
  alias Bonfire.Data.Social.Circle
  alias Bonfire.Boundaries.Verbs
  alias Bonfire.Me.Users
  alias Bonfire.Boundaries.Circles

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

  defmacro can?(controlled, user, verb), do: can(controlled, user, verb)

  defp can({controlled, _, _}, user, verb), do: can(controlled, user, verb)
  defp can(controlled, user, verb) when is_atom(controlled) do
    quote do
      require Ecto.Query
      require Bonfire.Boundaries.Queries
      verb = Bonfire.Data.AccessControl.Verbs.id!(unquote(verb))
      case unquote(user) do
        %{id: user_id, instance_admin: %{is_instance_admin: true}} ->
          unquote(admin_can(controlled))
        %{id: user_id} ->
          unquote(user_can(controlled))
        user_id when is_binary(user_id) ->
            unquote(user_can(controlled))
          _ ->
          unquote(guest_can(controlled))
      end
      |> Ecto.Query.subquery()
    end
  end

  # defp can_deprecated(controlled, user, verb) when is_atom(controlled) do
  #   quote do
  #     require Ecto.Query
  #     require Bonfire.Boundaries.Queries
  #     verb = Bonfire.Data.AccessControl.Verbs.id!(unquote(verb))
  #     Ecto.Query.from controlled in Bonfire.Data.AccessControl.Controlled,
  #       join: acl in assoc(controlled, :acl),
  #       join: grant in assoc(acl, :grants),
  #       join: access in assoc(grant, :access),
  #       join: interact in assoc(access, :interacts),
  #       left_join: circle in Bonfire.Data.Social.Circle,
  #       on: grant.subject_id == circle.id,
  #       left_join: encircle in assoc(circle, :encircles),
  #       where: interact.verb_id == ^verb,
  #       where: grant.subject_id in ^users or encircle.subject_id in ^users,
  #       where: controlled.id == parent_as(unquote(controlled)).id,
  #       group_by: [controlled.id],
  #       having: fragment("agg_perms(?)", interact.value),
  #       select: struct(interact, [:id])
  #   end
  # end

  # defp shared_can_deprecated(controlled, before, extra) do
  #   quote do
  #     unquote(before)
  #     Ecto.Query.from(controlled in Bonfire.Data.AccessControl.Controlled, [
  #       join: acl in assoc(controlled, :acl),
  #       join: grant in assoc(acl, :grants),
  #       join: access in assoc(grant, :access),
  #       join: interact in assoc(access, :interacts),
  #       left_join: circle in Bonfire.Data.Social.Circle,
  #       on: grant.subject_id == circle.id,
  #       where: interact.verb_id == ^verb,
  #       where: controlled.id == parent_as(unquote(controlled)).id,
  #       group_by: [controlled.id, interact.id],
  #       having: fragment("agg_perms(?)", interact.value),
  #       select: struct(interact, [:id]),
  #       # unquote_splicing(extra)
  #     ])
  #   end
  # end

  defp guest_can(controlled) do
    quote do
      guest_circle_id = Bonfire.Boundaries.Circles.circles()[:guest]
      Ecto.Query.from(controlled in Bonfire.Data.AccessControl.Controlled, [
        join: acl in assoc(controlled, :acl),
        join: grant in assoc(acl, :grants),
        join: access in assoc(grant, :access),
        join: interact in assoc(access, :interacts),
        left_join: circle in Bonfire.Data.Social.Circle,
        on: grant.subject_id == circle.id,
        where: interact.verb_id == ^verb,
        where: controlled.id == parent_as(unquote(controlled)).id,
        group_by: [controlled.id, interact.id],
        having: fragment("agg_perms(?)", interact.value),
        select: struct(interact, [:id]),
        # guest can:
        where: circle.id == ^guest_circle_id,
      ])
    end
  end

  defp user_can(controlled) do
    quote do
      Ecto.Query.from(controlled in Bonfire.Data.AccessControl.Controlled, [
        join: acl in assoc(controlled, :acl),
        join: grant in assoc(acl, :grants),
        join: access in assoc(grant, :access),
        join: interact in assoc(access, :interacts),
        left_join: circle in Bonfire.Data.Social.Circle,
        on: grant.subject_id == circle.id,
        where: interact.verb_id == ^verb,
        where: controlled.id == parent_as(unquote(controlled)).id,
        group_by: [controlled.id, interact.id],
        having: fragment("agg_perms(?)", interact.value),
        select: struct(interact, [:id]),
        # user can:
        left_join: encircle in assoc(circle, :encircles),
        where: grant.subject_id == ^user_id or encircle.subject_id == ^user_id,
      ])
    end
  end

  @doc "Checks if an admin OR the user can"
  defp admin_can(controlled) do
    quote do
      admin_circle_id = Bonfire.Boundaries.Circles.circles()[:admin]
      Ecto.Query.from(controlled in Bonfire.Data.AccessControl.Controlled, [
        join: acl in assoc(controlled, :acl),
        join: grant in assoc(acl, :grants),
        join: access in assoc(grant, :access),
        join: interact in assoc(access, :interacts),
        left_join: circle in Bonfire.Data.Social.Circle,
        on: grant.subject_id == circle.id,
        where: interact.verb_id == ^verb,
        where: controlled.id == parent_as(unquote(controlled)).id,
        group_by: [controlled.id, interact.id],
        having: fragment("agg_perms(?)", interact.value),
        select: struct(interact, [:id]),
        # admin or user can:
        left_join: encircle in assoc(circle, :encircles),
        where: circle.id == ^admin_circle_id or grant.subject_id == ^user_id or encircle.subject_id == ^user_id,
      ])
    end
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
  Lists permitted interactions on something for the current user.

  Parameters are the alias for the controlled item in the parent
  query and an expression evaluating to the current user.

  Currently requires a left lateral join. The final version may or may
  not, depending on how it is used.

  Does not recognise admins correctly right now, they're treated as regular users.
  """
  def permitted_on(controlled, user) do
    local = Users.local_user_id() # FIXME, what should this do?
    guest = Users.guest_user_id()
    quote do
      require Ecto.Query
      users = case unquote(user) do
        %{id: id} -> [id, unquote(local)]
        _ -> [unquote(guest)]
      end
      Ecto.Query.from controlled inon Bonfire.Data.AccessControl.Controlled,
        join: acl in assoc(controlled, :acl),
        join: grant in assoc(acl, :grants),
        join: access in assoc(grant, :access),
        join: interact in assoc(access, :interacts),
        left_join: circle in Bonfire.Data.Social.Circle,
        on: grant.subject_id == circle.id,
        left_join: encircle in assoc(circle, :encircles),
        where: grant.subject_id in ^users or encircle.subject_id in ^users,
        where: controlled.id == parent_as(unquote(controlled)).id,
        group_by: [controlled.id, interact.verb_id],
        having: Bonfire.Boundaries.Queries.agg_perms(interact.value),
        select: struct(interact, [:id, :verb_id])
    end
  end

end
