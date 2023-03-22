defmodule Bonfire.Boundaries.Web.CirclePreviewLive do
  use Bonfire.UI.Common.Web, :stateless_component
  # alias Bonfire.Boundaries.Circles

  prop parent_id, :string, default: nil
  prop members, :list
  prop count, :integer, default: nil
  prop size, :integer, default: 12
end
