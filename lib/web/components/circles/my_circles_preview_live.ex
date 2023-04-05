defmodule Bonfire.Boundaries.Web.MyCirclesPreviewLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Boundaries.Integration
  alias Bonfire.Boundaries.LiveHandler

  prop selected_tab, :string, default: "timeline"
  prop loading, :boolean, default: false
  prop hide_tabs, :boolean, default: false
  prop showing_within, :atom, default: :profile
  prop user, :map

  slot header
  slot widget
end
