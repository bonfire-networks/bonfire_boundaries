defmodule Bonfire.Boundaries.Web.RolesLive do
  use Bonfire.UI.Common.Web, :stateful_component
  # alias Bonfire.Boundaries.LiveHandler
  # alias Bonfire.Boundaries.Integration

  def update(assigns, socket) do
    # current_user = current_user(assigns)
    # params = e(assigns, :__context__, :current_params, %{})

    scope = e(assigns, :scope, nil) || e(socket.assigns, :scope, nil)

    verbs = Bonfire.Boundaries.Verbs.list(:db, :id)

    verbs =
      if scope != :instance do
        instance_verbs =
          Bonfire.Boundaries.Verbs.list(:instance, :id)
          |> debug

        verbs
        |> Enum.reject(&(elem(&1, 0) in instance_verbs))
        |> debug
      else
        verbs
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(verbs: verbs)}
  end
end
