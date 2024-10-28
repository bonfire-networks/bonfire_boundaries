defmodule Bonfire.Boundaries.Web.SearchUsersInCirclesLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Boundaries.Circles
  alias Bonfire.Boundaries.Blocks

  prop preloaded_recipients, :list, default: nil
  prop to_boundaries, :any, default: nil
  prop to_circles, :list, default: []
  prop exclude_circles, :list, default: []
  prop context_id, :string, default: nil
  prop showing_within, :atom, default: nil
  prop implementation, :any, default: :live_select
  prop label, :string, default: nil
  prop mode, :atom, default: :tags

  prop class, :string,
    default:
      "w-full h-10 input !border-none !border-b !border-base-content/10 !rounded-none select_recipients_input"

  prop is_editable, :boolean, default: false

  def handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket) do
    # current_user = current_user(assigns(socket))
    do_results_for_multiselect(search)
    |> maybe_send_update(LiveSelect.Component, live_select_id, options: ...)

    {:noreply, socket}
  end

  def do_results_for_multiselect(search) do
    Bonfire.Common.Utils.maybe_apply(
      Bonfire.Me.Users,
      :search,
      [search]
    )
    |> Bonfire.Boundaries.Web.SetBoundariesLive.results_for_multiselect()
  end

  def handle_event("multi_select", %{data: data, text: _text}, socket) do
    add_member(input_to_atoms(data), socket)
  end

  def add_member(subject, %{assigns: %{scope: scope, circle_type: circle_type}} = socket)
      when circle_type in [:silence, :ghost] do
    with id when is_binary(id) <- uid(subject),
         {:ok, _} <- Blocks.block(id, circle_type, scope || current_user(assigns(socket))) do
      {:noreply,
       socket
       |> assign_flash(:info, l("Blocked!"))
       |> assign(
         members:
           Map.merge(
             %{id => subject},
             e(assigns(socket), :members, %{})
           )
           |> debug()
       )}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not block"))}
    end
  end

  def add_member(subject, socket) do
    with id when is_binary(id) <- uid(subject),
         {:ok, _} <- Circles.add_to_circles(id, e(assigns(socket), :circle, nil)) do
      {:noreply,
       socket
       |> assign_flash(:info, l("Added to circle!"))
       |> assign(
         members:
           Map.merge(
             %{id => subject},
             e(assigns(socket), :members, %{})
           )
           |> debug()
       )}
    else
      other ->
        error(other)

        {:noreply, assign_flash(socket, :error, l("Could not add to circle"))}
    end
  end
end
