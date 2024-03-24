defmodule Bonfire.Boundaries.Web.BoundariesGeneralAccessLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Boundaries.LiveHandler

  prop boundary_preset, :any, default: nil
  prop to_boundaries, :any, default: nil
  prop my_acls, :any, default: nil
  prop scope, :any, default: :user
  prop is_dropdown, :boolean, default: false
  prop include_stereotypes, :boolean, default: false
  prop hide_presets, :boolean, default: false
  prop hide_custom, :boolean, default: false
  prop set_action, :string, default: nil
  prop set_opts, :map, default: %{}

  def matches?({preset, _}, preset), do: true
  def matches?([{preset, _}], preset), do: true
  def matches?(preset, preset), do: true
  def matches?(_, _), do: false

  def render(%{my_acls: nil} = assigns) do
    # debug(assigns)
    # should be loading this only once per persistent session, or when we open the composer
    assigns
    |> assign(
      my_acls:
        if assigns[:scope] == :user do
          e(assigns[:__context__], :my_acls, nil) || LiveHandler.my_acls(current_user_id(assigns))
        else
          LiveHandler.my_acls(:instance)
        end
    )
    |> render_sface()
  end

  def render(assigns) do
    assigns
    |> render_sface()
  end
end
