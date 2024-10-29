defmodule Bonfire.Boundaries.Web.DefaultBoundaryLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop scope, :any, default: nil

  # declare_settings_component(l("Default boundary"), icon: "fluent:people-team-16-filled")
end
