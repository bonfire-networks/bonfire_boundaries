defmodule Bonfire.Boundaries.Web.MyAclsLive do
  use Bonfire.UI.Common.Web, :stateful_component

  def update(assigns, socket) do
    acls = Bonfire.Boundaries.Acls.list_my(current_user(assigns)) #|> IO.inspect
    debug(acls, "Acls")

    {:ok, assign(socket,
    %{
      acls: acls,
      settings_section_title: "Create and manage your boundaries",
      settings_section_description: "Create and manage your boundaries."
      })}
  end

  def handle_event(action, attrs, socket), do: Bonfire.UI.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)

end
