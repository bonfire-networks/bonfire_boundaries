defmodule Bonfire.Boundaries.Web.BoundariesLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  import Untangle
  import Bonfire.Boundaries.Integration, only: [is_admin?: 1]
  alias Bonfire.UI.Me.LivePlugs
  alias Bonfire.Boundaries.Circles

  declare_extension(
    "Boundaries",
    icon: "twemoji:handshake",
    exclude_from_nav: true
  )

  # declare_settings_nav_link(:extension,
  #   # verb: :tag,
  #   scope: :user
  # )

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
        page_title: l("Boundaries & Circles"),
        nav_items: nav_items(),
        id: nil,
        back: true,
        page: "boundaries",
        sidebar_widgets: [
          users: [
            secondary: [
              {Bonfire.Tag.Web.WidgetTagsLive, []}
            ]
          ],
          guests: [
            secondary: nil
          ]
        ]
      )
    }

    # |> IO.inspect
  end

  defp nav_items(tab \\ nil)

  defp nav_items("instance" <> _),
    do: [Bonfire.UI.Common.InstanceSidebarSettingsNavLive.declared_nav()]

  defp nav_items(_), do: [Bonfire.UI.Common.SidebarSettingsNavLive.declared_nav()]

  def do_handle_params(%{"tab" => tab, "id" => id}, _url, socket) do
    # debug(id)
    {:noreply,
     assign(socket,
       selected_tab: tab,
       nav_items: nav_items(tab),
       id: id
     )}
  end

  def do_handle_params(%{"tab" => "circles" = tab}, _url, socket) do
    {:noreply,
     assign(
       socket,
       selected_tab: tab,
      #  page_header_icon: "material-symbols:group-work",
       page_title: l("My circles"),
       page_header_aside: [
         {Bonfire.Boundaries.Web.NewCircleButtonLive,
          [
            scope: :user,
            myself: e(socket, :myself, nil),
            setting_boundaries: false
          ]}
       ],
       nav_items: nav_items(tab)
     )}
  end

  def do_handle_params(%{"tab" => "acls" = tab}, _url, socket) do
    {:noreply,
     assign(
       socket,
       selected_tab: tab,
       page_title: l("My boundaries"),
       page_header_aside: [
         {Bonfire.Boundaries.Web.NewAclButtonLive,
          [
            scope: :user,
            myself: e(socket, :myself, nil),
            setting_boundaries: false
          ]}
       ],
       nav_items: nav_items(tab)
     )}
  end

  def do_handle_params(%{"tab" => "roles" = tab}, _url, socket) do
    {:noreply,
     assign(
       socket,
       selected_tab: tab,
       page_title: l("Default roles"),
       nav_items: nav_items(tab)
     )}
  end

  def do_handle_params(%{"tab" => tab}, _url, socket) do
    {:noreply,
     assign(
       socket,
       selected_tab: tab,
       nav_items: nav_items(tab)
     )}
  end

  def do_handle_params(_, _url, socket) do
    {:noreply, socket}
  end

  def handle_params(params, uri, socket),
    do:
      Bonfire.UI.Common.LiveHandlers.handle_params(
        params,
        uri,
        socket,
        __MODULE__,
        &do_handle_params/3
      )

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
          __MODULE__
          # &do_handle_event/3
        )

  def handle_info(info, socket),
    do: Bonfire.UI.Common.LiveHandlers.handle_info(info, socket, __MODULE__)
end
