defmodule Bonfire.Boundaries.Web.BoundaryComposerActionsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop done_label, :string, default: nil
  prop hide_preview, :boolean, default: nil
end
