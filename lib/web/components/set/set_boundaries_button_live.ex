defmodule Bonfire.Boundaries.Web.SetBoundariesButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component
  use Bonfire.Common.Utils

  prop preset_boundary, :any, default: nil
end
