defmodule Bonfire.Boundaries.Web.BoundariesLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  # import Untangle

  # alias Bonfire.Boundaries.Circles

  declare_extension(
    "Boundaries",
    icon: "twemoji:handshake",
    emoji: "🤝",
    exclude_from_nav: true
  )

  # declare_settings_nav_link(:extension,
  #   # verb: :tag,
  #   scope: :user
  # )

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(params, _session, socket) do
    {
      :ok,
      # |> assign(:without_sidebar,  true)
      assign(
        socket,
        selected_tab: "user",
        # page_title: l("Boundaries & Circles"),
        nav_items: Bonfire.Common.ExtensionModule.default_nav(),
        id: nil,
        back: true,
        page: "boundaries",
        scope: nil,
        current_params: params,
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

  # defp nav_items(tab \\ nil)

  # defp nav_items("instance"),
  #   do: [Bonfire.UI.Common.InstanceSidebarSettingsNavLive.declared_nav()]

  # defp nav_items(:instance),
  #   do: [Bonfire.UI.Common.InstanceSidebarSettingsNavLive.declared_nav()]

  # defp nav_items("instance" <> _),
  #   do: [Bonfire.UI.Common.InstanceSidebarSettingsNavLive.declared_nav()]

  # defp nav_items(_), do: [Bonfire.UI.Common.SidebarSettingsNavLive.declared_nav()]

  def do_handle_params(%{"tab" => tab, "id" => id} = params, _url, socket) do
    # debug(id)
    {:noreply,
     assign(socket,
       selected_tab: tab,
       #  nav_items: nav_items(params["scope"] || tab),
       id: id,
       scope: maybe_to_atom(params["scope"])
     )}
  end

  def do_handle_params(%{"tab" => tab, "id" => id, "section" => section} = params, _url, socket) do
    {:noreply,
     assign(socket,
       selected_tab: tab,
       #  nav_items: nav_items(params["scope"] || tab),
       id: id,
       section: section,
       scope: maybe_to_atom(params["scope"])
     )}
  end

  def do_handle_params(%{"tab" => "circles" = tab} = params, _url, socket) do
    scope = maybe_to_atom(params["scope"])

    {:noreply,
     assign(
       socket,
       selected_tab: tab,
       #  page_header_icon: "material-symbols:group-work-outline",
       page_title: l("Circles"),
       page_header_aside: [
         {Bonfire.Boundaries.Web.NewCircleButtonLive,
          [
            scope: scope,
            setting_boundaries: false
          ]}
       ],
       #  nav_items: nav_items(params["scope"] || tab),
       scope: scope
     )}
  end

  def do_handle_params(%{"tab" => "acls" = tab} = params, _url, socket) do
    scope = maybe_to_atom(params["scope"])

    {:noreply,
     assign(
       socket,
       selected_tab: tab,
       section: params["id"],
       page_title: l("Boundary Presets"),
       page_header_aside: [
         {Bonfire.Boundaries.Web.NewAclButtonLive,
          [
            setting_boundaries: false,
            scope: scope
          ]}
       ],
       #  nav_items: nav_items(params["scope"] || tab),
       scope: scope
     )}
  end

  def do_handle_params(%{"tab" => "roles" = tab} = params, _url, socket) do
    {:noreply,
     assign(
       socket,
       selected_tab: tab,
       page_title: l("Default roles"),
       #  nav_items: nav_items(params["scope"] || tab),
       scope: maybe_to_atom(params["scope"])
     )}
  end

  def do_handle_params(%{"tab" => tab} = params, _url, socket) do

    {:noreply,
     assign(
       socket,
       selected_tab: tab,
       #  nav_items: nav_items(params["scope"] || tab),
       scope: maybe_to_atom(params["scope"])
     )}
  end

  def do_handle_params(params, _url, socket) do
    {:noreply,
     assign(socket,
       #  nav_items: nav_items(params["scope"]),
       scope: maybe_to_atom(params["scope"])
     )}
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
