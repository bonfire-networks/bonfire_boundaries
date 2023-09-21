defmodule Bonfire.Boundaries.Web.RoleDetailsLive do
  use Bonfire.UI.Common.Web, :stateless_component
  # alias Bonfire.Boundaries.Verbs

  prop role, :any, required: true
  prop name, :string, default: nil
  prop read_only, :boolean, default: false

  prop available_verbs, :list
  prop all_verbs, :list

  prop event_target, :any, default: nil

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end
end
