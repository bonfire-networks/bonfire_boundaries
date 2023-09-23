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
    # debug(assigns)
    # TODO: only load this once per persistent session, or when we open the composer
    assigns
    |> assign(
      :my_acls,
      Bonfire.Boundaries.Acls.list_my(
        current_user_id(assigns),
        Bonfire.Boundaries.Acls.opts_for_dropdown()
      )
      # |> debug("myacccl")
      |> Enum.map(fn
        %Bonfire.Data.AccessControl.Acl{id: _acl_id} = acl ->
          acl_meta(acl)
      end)
      |> Enum.reject(&is_nil(&1.name))
    )
    |> render_sface()
  end

  def render(assigns) do
    assigns
    |> render_sface()
  end

  def acl_meta(%{id: acl_id, stereotyped: %{stereotype_id: "1HANDP1CKEDZEPE0P1E1F0110W"}} = acl) do
    %{
      id: acl_id,
      field: :to_boundaries,
      description: e(acl, :stereotyped, :named, :name, nil),
      name: l("Follows"),
      icon: "fluent:people-list-16-filled"
    }
  end

  def acl_meta(%{id: acl_id} = acl) do
    %{
      id: acl_id,
      field: :to_boundaries,
      description: e(acl, :extra_info, :summary, nil),
      name: e(acl, :named, :name, nil) || e(acl, :stereotyped, :named, :name, nil)
    }
  end
end
