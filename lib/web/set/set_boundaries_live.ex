defmodule Bonfire.Boundaries.Web.SetBoundariesLive do
  use Bonfire.UI.Common.Web, :stateless_component
  use Bonfire.Common.Utils

  prop create_activity_type, :any
  prop to_boundaries, :list
  prop to_circles, :list
  prop showing_within, :any
  prop show_select_recipients, :boolean, default: false
  prop open_boundaries, :boolean, default: false

end
