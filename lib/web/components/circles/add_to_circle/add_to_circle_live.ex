defmodule Bonfire.Boundaries.Web.AddToCircleLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Boundaries.Web.AddToCircleWidgetLive

  prop circles, :list, default: []
  prop user_id, :any, default: nil
  prop parent_id, :any, default: nil
  prop name, :any, default: nil
end
