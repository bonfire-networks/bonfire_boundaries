defmodule Bonfire.Boundaries.Web.BoundariesListLive do
  use Bonfire.UI.Common.Web, :stateless_component
  use Bonfire.Common.Utils

  prop create_activity_type, :any
  prop to_boundaries, :list
  prop to_boundaries_ids, :list, default: []
  prop to_circles, :list
  prop showing_within, :any
  prop show_select_recipients, :boolean, default: false
  prop open_boundaries, :boolean, default: false
  prop hide_breakdown, :boolean, default: false
  prop setting_boundaries, :boolean, default: false
  prop click_override, :boolean, default: false
  prop select_event, :string, default: nil

end
