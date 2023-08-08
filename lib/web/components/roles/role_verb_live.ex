defmodule Bonfire.Boundaries.Web.RoleVerbLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop verb, :any, required: true
  prop value, :boolean, default: nil
  prop read_only, :boolean, default: false
  prop mini, :boolean, default: false
  prop all_verbs, :list
  # prop exclude_verbs, :list, default: []

  prop event_target, :any, default: nil
  prop field_name, :any, default: nil

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end
end
