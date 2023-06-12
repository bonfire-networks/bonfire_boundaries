defmodule Bonfire.Boundaries.Web.RolesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  alias Bonfire.Boundaries.Roles

  prop scope, :any, default: :user

  def update(assigns, socket) do
    current_user = current_user(assigns) || current_user(socket)
    # params = e(assigns, :__context__, :current_params, %{})

    scope =
      (e(assigns, :scope, nil) || e(socket.assigns, :scope, nil))
      |> debug("role_scope")

    send_self(
      page_title: e(socket.assigns, :name, nil) || l("Roles"),
      back: true,
      page_header_aside: [
        {Bonfire.Boundaries.Web.NewRoleButtonLive, [scope: scope]}
      ]
    )

    available_verbs = Bonfire.Boundaries.Verbs.list(:code, :id)
    # |> debug()

    # available_verbs =
    #   if scope != :instance do
    #     instance_verbs =
    #       Bonfire.Boundaries.Verbs.list(:instance, :id)
    #       |> debug()

    #     available_verbs
    #     |> Enum.reject(&(elem(&1, 0) in instance_verbs))
    #   else
    #     available_verbs
    #   end
    #   |> debug()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       role_verbs:
         Bonfire.Boundaries.Roles.role_verbs(nil, scope: scope, current_user: current_user),
       #  negative_role_verbs: Bonfire.Boundaries.Roles.negative_role_verbs(),
       all_verbs: Bonfire.Boundaries.Verbs.verbs(),
       available_verbs: available_verbs
     )
     |> debug()}
  end

  def do_handle_event("edit_verb_value", %{"role" => roles} = attrs, socket) do
    debug(attrs)

    current_user = current_user_required!(socket)
    scope = e(socket.assigns, :scope, nil)
    # verb_value = List.first(Map.values(roles))
    grant =
      Enum.flat_map(roles, fn {role_name, verb_value} ->
        Enum.flat_map(verb_value, fn {verb, value} ->
          debug(scope, "edit #{role_name} -- #{verb} = #{value} - scope:")

          [
            Roles.edit_verb_permission(role_name, verb, value,
              scope: scope,
              current_user: current_user
            )
          ]
        end)
      end)

    # |> debug("done")
    with [ok: edited] <- grant do
      debug(edited)

      {
        :noreply,
        socket
        |> assign_flash(:info, l("Permission edited!"))
      }
    else
      other ->
        error(other)

        {:noreply, assign_error(socket, l("Could not edit permission"))}
    end
  end

  def handle_event(
        action,
        attrs,
        socket
      ),
      do:
        Bonfire.UI.Common.LiveHandlers.handle_event(
          action,
          attrs,
          socket,
          __MODULE__,
          &do_handle_event/3
        )
end
