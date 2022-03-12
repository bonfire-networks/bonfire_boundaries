defmodule Bonfire.Boundaries.Integration do
  alias Bonfire.Common.Config
  alias Bonfire.Common.Utils
  import Where

  def repo, do: Config.get!(:repo_module)

  def is_admin?(user) do
    if Map.get(user, :instance_admin) do
      Map.get(user.instance_admin, :is_instance_admin)
    else
      false # FIXME
    end
  end

  def is_local?(thing) do
    if Bonfire.Common.Utils.module_enabled?(Bonfire.Federate.ActivityPub.Utils) do
      Bonfire.Federate.ActivityPub.Utils.is_local?(thing)
    end
  end

end
