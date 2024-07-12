defmodule Bonfire.Boundaries.Web.InstanceSidebarNavLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :any
  prop id, :string, default: nil

  prop class, :css_class, default: "!p-0 !m-0"

  declare_settings_nav_component("Links to boundaries & circles management pages",
    scope: :instance
  )
end
