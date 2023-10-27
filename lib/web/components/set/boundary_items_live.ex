defmodule Bonfire.Boundaries.Web.BoundaryItemsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop to_boundaries, :any, default: nil
  prop circles, :any, default: []
  prop roles_for_dropdown, :any, default: nil
  prop field, :atom, default: :to_circles
  prop read_only, :boolean, default: false

  slot default, required: false

  def acls_from_role(role) do
    {:ok, permissions, []} = Bonfire.Boundaries.Roles.verbs_for_role(maybe_to_atom(role), %{})
    permissions
  end

  def name(data) when is_binary(data), do: data
  def name(data) when is_tuple(data), do: elem(data, 1)

  def name(data) when is_map(data),
    do:
      e(data, :name, nil) || e(data, :profile, :name, nil) || e(data, :named, :name, nil) ||
        e(data, :stereotyped, :named, :name, nil)

  def name(data) do
    warn(data, "Dunno how to display")
    nil
  end
end
