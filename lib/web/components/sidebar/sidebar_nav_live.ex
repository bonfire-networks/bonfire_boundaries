defmodule Bonfire.Boundaries.Web.SidebarNavLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop selected_tab, :any
  prop id, :string, default: nil
  prop showing_within, :atom, default: :sidebar
  prop class, :css_class, default: "!p-0 !m-0"

  declare_nav_component("Links to boundaries & circles management pages")
  declare_settings_nav_component("Links to boundaries & circles management pages", scope: :user)
end
