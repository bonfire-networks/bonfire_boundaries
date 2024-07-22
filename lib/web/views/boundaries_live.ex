defmodule Bonfire.Boundaries.Web.BoundariesLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  # import Untangle

  # alias Bonfire.Boundaries.Circles

  declare_extension(
    "Boundaries",
    icon: "fa6-solid:handshake-angle",
    emoji: "🤝",
    description:
      l(
        "Circles, roles, and boundaries for user control around sharing, privacy, and collaboration."
      ),
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
      assign(
        socket,
        selected_tab: "user",
        without_secondary_widgets: true,
        nav_items:
          List.wrap(
            maybe_apply(Bonfire.UI.Me.SidebarSettingsNavLive, :declared_nav, [],
              fallback_return: []
            )
          ),
        id: nil,
        back: true,
        page: "boundaries",
        scope: nil,
        current_params: params
      )
    }

    # |> IO.inspect
  end

  # defp nav_items(tab \\ nil)

  # defp nav_items("instance"),
  #   do: [Bonfire.UI.Me.InstanceSidebarSettingsNavLive.declared_nav()]

  # defp nav_items(:instance),
  #   do: [Bonfire.UI.Me.InstanceSidebarSettingsNavLive.declared_nav()]

  # defp nav_items("instance" <> _),
  #   do: [Bonfire.UI.Me.InstanceSidebarSettingsNavLive.declared_nav()]

  # defp nav_items(_), do: [Bonfire.UI.Me.SidebarSettingsNavLive.declared_nav()]

  def handle_params(%{"tab" => tab, "id" => id} = params, _url, socket) do
    # debug(id)
    {:noreply,
     assign(socket,
       selected_tab: tab,
       #  nav_items: nav_items(params["scope"] || tab),
       id: id,
       scope: maybe_to_atom(params["scope"])
     )}
  end

  def handle_params(%{"tab" => tab, "id" => id, "section" => section} = params, _url, socket) do
    {:noreply,
     assign(socket,
       selected_tab: tab,
       #  nav_items: nav_items(params["scope"] || tab),
       id: id,
       section: section,
       scope: maybe_to_atom(params["scope"])
     )}
  end

  def handle_params(%{"tab" => "circles" = tab} = params, _url, socket) do
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

  def handle_params(%{"tab" => "acls" = tab} = params, _url, socket) do
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

  def handle_params(%{"tab" => "roles" = tab} = params, _url, socket) do
    {:noreply,
     assign(
       socket,
       selected_tab: tab,
       page_title: l("Roles"),
       #  nav_items: nav_items(params["scope"] || tab),
       scope: maybe_to_atom(params["scope"])
     )}
  end

  def handle_params(%{"tab" => tab} = params, _url, socket) do
    {:noreply,
     assign(
       socket,
       selected_tab: tab,
       #  nav_items: nav_items(params["scope"] || tab),
       scope: maybe_to_atom(params["scope"])
     )}
  end

  def handle_params(params, _url, socket) do
    {:noreply,
     assign(socket,
       #  nav_items: nav_items(params["scope"]),
       scope: maybe_to_atom(params["scope"])
     )}
  end
end
