defmodule Bonfire.Boundaries.Web.BoundariesLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  import Untangle
  import Bonfire.Boundaries.Integration, only: [is_admin?: 1]
  alias Bonfire.UI.Me.LivePlugs

  declare_extension("Boundaries", icon: "twemoji:handshake", exclude_from_nav: true)

  declare_settings_nav_link(:extension,
    # verb: :tag,
    scopes: [:user, :instance]
  )

  def mount(params, session, socket) do
    live_plug(params, session, socket, [
      LivePlugs.LoadCurrentAccount,
      LivePlugs.LoadCurrentUser,
      LivePlugs.UserRequired,
      Bonfire.UI.Common.LivePlugs.StaticChanged,
      Bonfire.UI.Common.LivePlugs.Csrf,
      Bonfire.UI.Common.LivePlugs.Locale,
      &mounted/3
    ])
  end

  defp mounted(_params, _session, socket) do
    {
      :ok,
      # |> assign(:without_sidebar,  true)
      assign(
        socket,
        selected_tab: "user",
        show_less_menu_items: true,
        page_title: l("Boundaries & Circles"),
        page_header_aside: [
          {Bonfire.UI.Me.SettingsViewsLive.HeaderAsideMobileMenuLive, []}
        ],
        id: nil,
        page: "boundaries"
      )
    }

    # |> IO.inspect
  end

  def do_handle_params(%{"tab" => tab, "id" => id}, _url, socket) do
    # debug(id)
    {:noreply,
     assign(socket,
       selected_tab: tab,
       id: id
     )}
  end

  def do_handle_params(%{"tab" => tab}, _url, socket) do
    {:noreply,
     assign(
       socket,
       selected_tab: tab
     )}
  end

  def do_handle_params(_, _url, socket) do
    {:noreply, socket}
  end

  def handle_params(params, uri, socket) do
    # poor man's hook I guess
    with {_, socket} <-
           Bonfire.UI.Common.LiveHandlers.handle_params(params, uri, socket) do
      undead_params(socket, fn ->
        do_handle_params(params, uri, socket)
      end)
    end
  end

  def handle_event(action, attrs, socket),
    do:
      Bonfire.UI.Common.LiveHandlers.handle_event(
        action,
        attrs,
        socket,
        __MODULE__
      )
end
