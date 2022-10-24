defmodule Bonfire.Boundaries.Integration do
  alias Bonfire.Common.Config
  # alias Bonfire.Common.Utils
  # import Untangle

  def repo, do: Config.repo()

  def is_admin?(user) do
    if is_map(user) and Map.get(user, :instance_admin) do
      Map.get(user.instance_admin, :is_instance_admin)
    else
      # FIXME
      false
    end
  end

  def is_local?(thing) do
    if Bonfire.Common.Extend.module_enabled?(Bonfire.Federate.ActivityPub.Utils) do
      Bonfire.Federate.ActivityPub.Utils.is_local?(thing)
    end
  end
end
