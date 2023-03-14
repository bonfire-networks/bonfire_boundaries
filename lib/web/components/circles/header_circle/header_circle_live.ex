defmodule Bonfire.Boundaries.Web.HeaderCircleLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop circle, :map, required: true
  prop stereotype_id, :string, default: nil
  prop read_only, :boolean, default: false
  prop suggestions, :list, default: []
end
