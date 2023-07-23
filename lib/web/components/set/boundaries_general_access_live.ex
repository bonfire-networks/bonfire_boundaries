defmodule Bonfire.Boundaries.Web.BoundariesGeneralAccessLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop boundary_preset, :any, default: nil
  prop to_boundaries, :any, default: nil
  prop my_acls, :any, default: nil
  prop is_dropdown, :boolean, default: false

  def matches?({preset, _}, preset), do: true
  def matches?([{preset, _}], preset), do: true
  def matches?(_, _), do: false

  def render(%{my_acls: nil} = assigns) do
    # TODO: only load this once per persistent session, or when we open the composer
    assigns
    |> assign(
      :my_acls,
      Bonfire.Boundaries.Acls.list_my(
        current_user(assigns),
        Bonfire.Boundaries.Acls.opts_for_dropdown()
      )
      # |> debug("myacccl")
      |> Enum.map(fn
        %Bonfire.Data.AccessControl.Acl{id: acl_id} = acl ->
          %{
            id: acl_id,
            field: :to_boundaries,
            description: e(acl, :extra_info, :summary, nil),
            name: e(acl, :named, :name, nil) || e(acl, :stereotyped, :named, :name, nil)
          }
      end)
      |> Enum.reject(&is_nil(&1.name))
    )
    |> render_sface()
  end

  def render(assigns) do
    assigns
    |> render_sface()
  end
end
